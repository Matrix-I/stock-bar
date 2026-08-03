// WatchlistCodingTests.swift — the storage format's one promise: a build never deletes what it can't read.
//
// These are regression tests for a list that was actually lost. An older copy of the app, still registered
// as the login item, read a blob containing a market it had never heard of, threw away the entire array
// over that one row, and then saved the shipped defaults over it. So the cases below are written from the
// old build's point of view: a row from the future is the input, and what matters is what survives.
//
// The fictional "hongkong" market stands in for that future. It has to be a value Core genuinely does not
// know — using `world` would prove nothing here, since this build understands it.

import Testing
import Foundation
@testable import StockBarCore

@Suite("WatchlistCoding")
struct WatchlistCodingTests {

    private let vcb = WatchedSymbol(symbol: "VCB", market: .vietnam, pinnedToMenuBar: false)
    private let btc = WatchedSymbol(symbol: "BTCUSDT", market: .crypto, pinnedToMenuBar: true)

    /// A blob as a later version would have written it: two rows this build reads, one it cannot.
    private var blobWithAFutureRow: Data {
        Data("""
        [{"symbol":"VCB","market":"vietnam","pinnedToMenuBar":false},
         {"symbol":"HSI","market":"hongkong","pinnedToMenuBar":true},
         {"symbol":"BTCUSDT","market":"crypto","pinnedToMenuBar":true}]
        """.utf8)
    }

    private func rows(in data: Data) -> [[String: Any]] {
        let object = try? JSONSerialization.jsonObject(with: data)
        return (object as? [Any])?.compactMap { $0 as? [String: Any] } ?? []
    }

    // MARK: What a build can read

    @Test("A row from a later version costs that row, not the whole list")
    func unknownMarketKeepsTheRest() {
        let stored = WatchlistCoding.decode(blobWithAFutureRow)
        #expect(stored?.symbols == [vcb, btc])
        #expect(stored?.carried.foreignRows.count == 1)
        // The all-or-nothing decode this replaced returned nil here, and the caller then showed — and
        // saved — the four shipped defaults. That is the whole bug, in one assertion.
        #expect(stored?.symbols.isEmpty == false)
    }

    @Test("A blob that isn't a JSON array is the one real loss, and it says so")
    func garbageIsNil() {
        #expect(WatchlistCoding.decode(Data("not json at all".utf8)) == nil)
        // An object rather than an array: written by nothing this app has ever shipped, so there is no row
        // order to salvage and the caller has to fall back.
        #expect(WatchlistCoding.decode(Data(#"{"symbol":"VCB"}"#.utf8)) == nil)
    }

    @Test("An empty list is a choice, not a failure")
    func emptyArrayDecodes() {
        // Distinguished from nil on purpose: "I removed every row" must not be answered by silently
        // restoring the shipped defaults over the top of it.
        let stored = WatchlistCoding.decode(Data("[]".utf8))
        #expect(stored == WatchlistCoding.Stored(symbols: [], carried: .none))
    }

    @Test("A blob written by a plain JSONEncoder still reads")
    func readsTheOldFormat() {
        // Every version up to now wrote exactly this. The format did not change; only the reading did.
        let old = try? JSONEncoder().encode([vcb, btc])
        #expect(WatchlistCoding.decode(old ?? Data())?.symbols == [vcb, btc])
    }

    // MARK: What a save puts back

    @Test("Saving puts the unreadable row back, at the index it held")
    func foreignRowSurvivesASave() throws {
        let stored = try #require(WatchlistCoding.decode(blobWithAFutureRow))
        let written = try #require(WatchlistCoding.encode(stored.symbols, carrying: stored.carried))
        let out = rows(in: written)
        #expect(out.count == 3)
        #expect(out[1]["symbol"] as? String == "HSI")
        #expect(out[1]["market"] as? String == "hongkong")
        // And the round trip is stable: reading what we just wrote gives the same two readable rows back.
        #expect(WatchlistCoding.decode(written)?.symbols == [vcb, btc])
    }

    @Test("A field this build has no property for survives the save too")
    func unknownFieldSurvives() throws {
        // The same failure one level down. WatchedSymbol's decode ignores keys it doesn't know, so the row
        // reads fine — and re-encoding from the struct alone would drop the key without a word.
        let blob = Data("""
        [{"symbol":"VCB","market":"vietnam","pinnedToMenuBar":false,"alertAbove":70000}]
        """.utf8)
        let stored = try #require(WatchlistCoding.decode(blob))
        let written = try #require(WatchlistCoding.encode(stored.symbols, carrying: stored.carried))
        #expect(rows(in: written).first?["alertAbove"] as? Int == 70000)
    }

    @Test("This build's own fields win over the ones it was handed")
    func ourFieldsWin() throws {
        // Carrying a row forward must not mean freezing it: pinning VCB has to reach the blob even though
        // the stored copy of that row says otherwise.
        let stored = try #require(WatchlistCoding.decode(blobWithAFutureRow))
        var pinned = stored.symbols
        pinned[0].pinnedToMenuBar = true
        let written = try #require(WatchlistCoding.encode(pinned, carrying: stored.carried))
        #expect(rows(in: written).first?["pinnedToMenuBar"] as? Bool == true)
        #expect(WatchlistCoding.decode(written)?.symbols.first?.pinnedToMenuBar == true)
    }

    @Test("A carried row whose index is past the end of a shrunken list is still written")
    func foreignIndexIsClamped() throws {
        // The user removes the rows around it. Appending at the end is the only sane answer, and losing it
        // for being out of range is the answer that must not happen.
        let carried = WatchlistCoding.Carried(
            foreignRows: [.init(index: 9, json: Data(#"{"symbol":"HSI","market":"hongkong"}"#.utf8))],
            storedRows: [])
        let written = try #require(WatchlistCoding.encode([vcb], carrying: carried))
        let out = rows(in: written)
        #expect(out.count == 2)
        #expect(out.last?["symbol"] as? String == "HSI")
    }

    @Test("Two carried rows keep their order relative to each other")
    func foreignRowsKeepTheirOrder() throws {
        let blob = Data("""
        [{"symbol":"HSI","market":"hongkong","pinnedToMenuBar":false},
         {"symbol":"VCB","market":"vietnam","pinnedToMenuBar":false},
         {"symbol":"N100","market":"euronext","pinnedToMenuBar":false}]
        """.utf8)
        let stored = try #require(WatchlistCoding.decode(blob))
        let written = try #require(WatchlistCoding.encode(stored.symbols, carrying: stored.carried))
        #expect(rows(in: written).map { $0["symbol"] as? String } == ["HSI", "VCB", "N100"])
    }

    @Test("With nothing carried, the blob is what a plain JSONEncoder would have written")
    func staysReadableByOlderBuilds() throws {
        // Not a formatting claim — key order is not stable through JSONSerialization — but a compatibility
        // one: a build that decodes the whole array at once must still be able to read what we write.
        let written = try #require(WatchlistCoding.encode([vcb, btc], carrying: .none))
        #expect((try? JSONDecoder().decode([WatchedSymbol].self, from: written)) == [vcb, btc])
    }

    @Test("A list saved and reloaded is the same list")
    func roundTrip() throws {
        let list = [vcb, btc, WatchedSymbol(symbol: "DJI", market: .world, pinnedToMenuBar: false)]
        let written = try #require(WatchlistCoding.encode(list, carrying: .none))
        #expect(WatchlistCoding.decode(written)?.symbols == list)
    }
}
