// PriceLogTests.swift — the series this app keeps for itself, and the two ways it could fill with nothing.
//
// A recorder polled every minute for eight hours sees 480 readings of four distinct prices. Storing every
// reading is the failure that hides: the buffer fills with a flat line, the real history is pushed out of
// the far end, and the sparkline it draws is a straight horizontal stroke that looks like a working chart
// of a market that did not move.

import Testing
import Foundation
@testable import StockBarCore

@Suite("PriceLog")
struct PriceLogTests {

    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    private func later(_ minutes: Double) -> Date { t0.addingTimeInterval(minutes * 60) }

    private func quote(_ symbol: String, _ market: Market, _ price: Double, at: Date) -> Quote {
        Quote(symbol: symbol, market: market, price: price, reference: nil,
              ceiling: nil, floor: nil, volume: nil, asOf: at)
    }

    private func watched(_ symbol: String, _ market: Market) -> WatchedSymbol {
        WatchedSymbol(symbol: symbol, market: market, pinnedToMenuBar: false)
    }

    @Test("Only a changed price is recorded, so a quiet board does not fill the buffer")
    func recordsChangesNotObservations() {
        var log = PriceLog()
        // The gold board publishes once and is then polled for hours. Every one of those repeats must
        // collapse, or a buffer of history becomes a buffer of one morning.
        for minute in 0..<200 { log.record(144_000_000, at: later(Double(minute)), observed: later(Double(minute))) }
        #expect(log.points.count == 1)

        // Spaced past the floor, so what is being tested here is the change filter and not the clock.
        log.record(144_500_000, at: later(200), observed: later(200))
        log.record(144_500_000, at: later(201), observed: later(201))
        log.record(144_000_000, at: later(240), observed: later(240))
        #expect(log.closes == [144_000_000, 144_500_000, 144_000_000])
        // The timestamp is the first sighting at that level, not the latest repeat of it.
        #expect(log.points[0].at == t0)
        #expect(log.points[1].at == later(200))
    }

    @Test("A tick-driven row is spaced, so it cannot spend the whole buffer on one afternoon")
    func spacingFloor() {
        // GOLDGAP is arithmetic over a world spot price that moves every minute, so it differs at every
        // single poll and the change filter above passes all of it. Unspaced, this loop records 480 points
        // and a buffer sized for months holds eight hours.
        var log = PriceLog()
        for minute in 0..<480 {
            log.record(5_700_000 + Double(minute) * 1_000, at: later(Double(minute)),
                       observed: later(Double(minute)))
        }
        #expect(log.points.count == 16)   // minute 0, then one per half hour through minute 450

        // A move suppressed by the window is delayed, never lost: the price still differs at the next poll
        // past the floor, and is taken then. That is what makes the floor safe for a step function.
        var board = PriceLog()
        board.record(144_000_000, at: t0, observed: t0)
        board.record(144_500_000, at: later(5), observed: later(5))      // inside the window — held back
        #expect(board.closes == [144_000_000])
        board.record(144_500_000, at: later(31), observed: later(31))    // still differs, so now it lands
        #expect(board.closes == [144_000_000, 144_500_000])
    }

    @Test("An unchanged price does not spend the window")
    func quietPollsDoNotConsumeTheFloor() {
        // The window is spent by a RECORDED point and by nothing else — `lastObserved` moves only where a
        // point is appended. So a board polled all afternoon at one price arrives at its next real move
        // with the floor already behind it, and the move is taken the moment it is seen rather than up to
        // half an hour later. (The two guards may be written in either order for the same reason: neither
        // rejection path touches state. A mutant that swaps them survives, correctly.)
        var log = PriceLog()
        log.record(26_410, at: t0, observed: t0)
        for minute in 1...45 { log.record(26_410, at: later(Double(minute)), observed: later(Double(minute))) }
        log.record(26_420, at: later(46), observed: later(46))
        #expect(log.closes == [26_410, 26_420])
    }

    @Test("A price of zero is never recorded")
    func rejectsZero() {
        // The board reports 0 for a row that has not traded. Recording it would put a floor-to-ceiling
        // cliff in the middle of a sparkline and misprice everything the chart is normalised against.
        var log = PriceLog()
        log.record(0, at: t0, observed: t0)
        log.record(-5, at: later(1), observed: later(1))
        #expect(log.points.isEmpty)
        log.record(26_410, at: later(2), observed: later(2))
        log.record(0, at: later(40), observed: later(40))
        #expect(log.closes == [26_410])
    }

    @Test("The buffer is bounded and drops from the old end")
    func capacity() {
        var log = PriceLog()
        // Spaced an hour apart so every one of them clears the floor and the cap is what does the work.
        for i in 0..<(PriceLog.capacity + 40) {
            log.record(Double(1000 + i), at: later(Double(i) * 60), observed: later(Double(i) * 60))
        }
        #expect(log.points.count == PriceLog.capacity)
        // The newest survives and the oldest is gone — a ring that dropped the new end would freeze the
        // chart at whatever it first saw.
        #expect(log.closes.last == Double(1000 + PriceLog.capacity + 39))
        #expect(log.closes.first == Double(1000 + 40))
    }

    @Test("Only the rows no feed gives a series for are recorded")
    func selfRecordedRows() {
        #expect(PriceLog.isSelfRecorded(symbol: "SJC", market: .vietnam))
        #expect(PriceLog.isSelfRecorded(symbol: "USDVND", market: .vietnam))
        #expect(PriceLog.isSelfRecorded(symbol: "GOLDGAP", market: .vietnam))
        // Everything else has bars from its own feed, and a recorded series would be a second, shorter
        // answer to a question already answered.
        #expect(!PriceLog.isSelfRecorded(symbol: "VCB", market: .vietnam))
        #expect(!PriceLog.isSelfRecorded(symbol: "VNINDEX", market: .vietnam))
        #expect(!PriceLog.isSelfRecorded(symbol: "GOLD", market: .world))
        #expect(!PriceLog.isSelfRecorded(symbol: "BTCUSDT", market: .crypto))
    }

    @Test("A batch records the right rows and reports whether anything moved")
    func batch() {
        var logs = PriceLogs()
        let entries = [watched("SJC", .vietnam), watched("VCB", .vietnam), watched("GOLDGAP", .vietnam)]
        let first = [
            "vietnam:SJC": quote("SJC", .vietnam, 144_000_000, at: t0),
            "vietnam:VCB": quote("VCB", .vietnam, 59_700, at: t0),
            "vietnam:GOLDGAP": quote("GOLDGAP", .vietnam, 5_756_780, at: t0),
        ]
        // Hoisted out of `#expect`: the macro captures its expression as an autoclosure, so a mutating
        // call inside it cannot reach `logs`.
        let recorded = logs.record(entries, quotes: first, now: t0)
        #expect(recorded)
        #expect(logs["vietnam:SJC"]?.closes == [144_000_000])
        #expect(logs["vietnam:GOLDGAP"]?.closes == [5_756_780])
        // VCB has a feed series; recording it too would leave the merge deciding between two answers.
        #expect(logs["vietnam:VCB"] == nil)

        // The return value gates the disk write, so an unchanged poll — the normal case all afternoon —
        // must report false or the app re-encodes the whole blob once a minute for nothing. Asked an hour
        // later, well past the spacing floor, so it is the price and not the clock that answers.
        let again = logs.record(entries, quotes: first, now: later(60))
        #expect(!again)
    }

    @Test("A row whose publication stamp stands still is still spaced by the clock that moves")
    func spacedByTheObservingClock() {
        // The two dates in `record` are not interchangeable, and GOLDGAP is where that stops being a
        // technicality. Its `asOf` is the oldest of its three inputs — PNJ's publication time, which does
        // not move between board updates — while the gap itself moves with world gold all day. Space the
        // points by `asOf` and every reading looks simultaneous with the last: one point, forever, on a row
        // whose whole purpose is to accumulate a shape.
        var logs = PriceLogs()
        let entries = [watched("GOLDGAP", .vietnam)]
        let published = t0                      // the board stamp, fixed all afternoon
        var recorded = 0
        for poll in 0..<8 {
            let gap = 5_700_000 + Double(poll) * 25_000
            if logs.record(entries, quotes: ["vietnam:GOLDGAP":
                    quote("GOLDGAP", .vietnam, gap, at: published)], now: later(Double(poll) * 45)) {
                recorded += 1
            }
        }
        #expect(recorded == 8)
        #expect(logs["vietnam:GOLDGAP"]?.closes.count == 8)
        // Every point carries the same publication stamp, which is honest — and is exactly why it could
        // not have been the thing measuring the gaps between them.
        #expect(logs["vietnam:GOLDGAP"]?.points.allSatisfy { $0.at == published } == true)
    }

    @Test("A point recorded into a full buffer is still reported as a change")
    func fullBufferStillReportsAChange() {
        // At capacity an append is matched by a drop, so the count is identical before and after. A
        // change test that watches the count alone reports "nothing happened" for every poll from then
        // on — the log keeps accumulating in memory and the disk never hears another word, so the series
        // silently reverts to whatever was stored the last time it was still growing.
        var logs = PriceLogs()
        let entries = [watched("SJC", .vietnam)]
        for i in 0..<PriceLog.capacity {
            logs.record(entries, quotes: ["vietnam:SJC":
                    quote("SJC", .vietnam, 144_000_000 + Double(i) * 1_000, at: t0)],
                    now: later(Double(i) * 60))
        }
        #expect(logs["vietnam:SJC"]?.points.count == PriceLog.capacity)
        let changed = logs.record(entries, quotes: ["vietnam:SJC":
                quote("SJC", .vietnam, 999_000_000, at: t0)], now: later(Double(PriceLog.capacity) * 60))
        #expect(changed)
        #expect(logs["vietnam:SJC"]?.closes.last == 999_000_000)
        #expect(logs["vietnam:SJC"]?.points.count == PriceLog.capacity)
    }

    @Test("A row that leaves the watchlist takes its history with it")
    func prune() {
        var logs = PriceLogs()
        logs.record([watched("SJC", .vietnam), watched("USDVND", .vietnam)], quotes: [
            "vietnam:SJC": quote("SJC", .vietnam, 144_000_000, at: t0),
            "vietnam:USDVND": quote("USDVND", .vietnam, 26_410, at: t0),
        ], now: t0)
        let pruned = logs.prune(keeping: ["vietnam:SJC"])
        #expect(pruned)
        #expect(logs["vietnam:USDVND"] == nil)
        #expect(logs["vietnam:SJC"] != nil)
        // Idempotent, so the prune that runs on every poll does not report a change it did not make.
        let prunedAgain = logs.prune(keeping: ["vietnam:SJC"])
        #expect(!prunedAgain)
    }

    @Test("A stored log round-trips, since it outlives the process that wrote it")
    func codable() throws {
        var logs = PriceLogs()
        logs.record([watched("SJC", .vietnam)],
                    quotes: ["vietnam:SJC": quote("SJC", .vietnam, 144_000_000, at: t0)], now: t0)
        let round = try JSONDecoder().decode(PriceLogs.self, from: try JSONEncoder().encode(logs))
        #expect(round == logs)
        #expect(round["vietnam:SJC"]?.points.first?.at == t0)
        // The spacing floor has to survive the process too, or every relaunch is a free point and an app
        // restarted all day records exactly what the floor exists to prevent.
        #expect(round["vietnam:SJC"]?.lastObserved == t0)
    }

    @Test("A log stored before the spacing floor existed still decodes")
    func decodesAnOlderBlob() throws {
        // The WatchedSymbol trap, one type over: a property default does NOT make a Codable key optional,
        // so a non-optional `lastObserved` would have made every stored series undecodable and silently
        // thrown away the history this file exists to accumulate. Optional, and therefore decodeIfPresent.
        let old = #"{"logs":{"vietnam:SJC":{"points":[{"at":0,"price":144000000}]}}}"#
        let logs = try JSONDecoder().decode(PriceLogs.self, from: Data(old.utf8))
        #expect(logs["vietnam:SJC"]?.closes == [144_000_000])
        #expect(logs["vietnam:SJC"]?.lastObserved == nil)
    }
}
