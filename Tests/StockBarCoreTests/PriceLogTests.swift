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
        // collapse, or 120 slots of history become 120 readings of one morning.
        for minute in 0..<200 { log.record(144_000_000, at: later(Double(minute))) }
        #expect(log.points.count == 1)

        log.record(144_500_000, at: later(200))
        log.record(144_500_000, at: later(201))
        log.record(144_000_000, at: later(202))
        #expect(log.closes == [144_000_000, 144_500_000, 144_000_000])
        // The timestamp is the first sighting at that level, not the latest repeat of it.
        #expect(log.points[0].at == t0)
        #expect(log.points[1].at == later(200))
    }

    @Test("A price of zero is never recorded")
    func rejectsZero() {
        // The board reports 0 for a row that has not traded. Recording it would put a floor-to-ceiling
        // cliff in the middle of a sparkline and misprice everything the chart is normalised against.
        var log = PriceLog()
        log.record(0, at: t0)
        log.record(-5, at: later(1))
        #expect(log.points.isEmpty)
        log.record(26_410, at: later(2))
        log.record(0, at: later(3))
        #expect(log.closes == [26_410])
    }

    @Test("The buffer is bounded and drops from the old end")
    func capacity() {
        var log = PriceLog()
        for i in 0..<(PriceLog.capacity + 40) { log.record(Double(1000 + i), at: later(Double(i))) }
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
        let recorded = logs.record(entries, quotes: first)
        #expect(recorded)
        #expect(logs["vietnam:SJC"]?.closes == [144_000_000])
        #expect(logs["vietnam:GOLDGAP"]?.closes == [5_756_780])
        // VCB has a feed series; recording it too would leave the merge deciding between two answers.
        #expect(logs["vietnam:VCB"] == nil)

        // The return value gates the disk write, so an unchanged poll — the normal case all afternoon —
        // must report false or the app re-encodes the whole blob once a minute for nothing.
        let again = logs.record(entries, quotes: first)
        #expect(!again)
    }

    @Test("A row that leaves the watchlist takes its history with it")
    func prune() {
        var logs = PriceLogs()
        logs.record([watched("SJC", .vietnam), watched("USDVND", .vietnam)], quotes: [
            "vietnam:SJC": quote("SJC", .vietnam, 144_000_000, at: t0),
            "vietnam:USDVND": quote("USDVND", .vietnam, 26_410, at: t0),
        ])
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
                    quotes: ["vietnam:SJC": quote("SJC", .vietnam, 144_000_000, at: t0)])
        let round = try JSONDecoder().decode(PriceLogs.self, from: try JSONEncoder().encode(logs))
        #expect(round == logs)
        #expect(round["vietnam:SJC"]?.points.first?.at == t0)
    }
}
