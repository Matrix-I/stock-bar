// WorldIndexTests.swift — the table that turns a typed symbol into a feed symbol, a venue and a market.
//
// Every one of those mappings fails quietly when it is wrong: the caret dropped from ^DJI gets a 404 that
// looks like a network problem, a world index filed under .vietnam is asked of a Vietnamese board that has
// never heard of it, and an alias stored as typed becomes a second row quoting the same index.

import Testing
import Foundation
@testable import StockBarCore

@Suite("WorldIndex")
struct WorldIndexTests {

    @Test("Every listed index maps to the caret spelling the feed wants")
    func yahooSpelling() {
        #expect(WorldIndex.yahooSymbol(for: "DJI") == "^DJI")
        #expect(WorldIndex.yahooSymbol(for: "IXIC") == "^IXIC")
        // The one where the two spellings differ by more than a caret: the app's NI225 is Yahoo's ^N225.
        #expect(WorldIndex.yahooSymbol(for: "NI225") == "^N225")
        // Anything not in the table is forwarded as typed, which is what lets a Yahoo symbol this app has
        // never heard of still be watched.
        #expect(WorldIndex.yahooSymbol(for: "aapl") == "AAPL")
    }

    @Test("Aliases resolve to one canonical spelling before anything is stored")
    func aliases() {
        #expect(Ticker.canonical("n225") == "NI225")
        #expect(Ticker.canonical("^N225") == "NI225")
        #expect(Ticker.canonical(" djia ") == "DJI")
        #expect(Ticker.canonical("nasdaq") == "IXIC")
        // Not an alias: DOW is a real NYSE ticker (Dow Inc.), so treating it as the average would answer a
        // question nobody asked.
        #expect(Ticker.canonical("DOW") == "DOW")
        // Everything else is left alone beyond trimming and upper-casing.
        #expect(Ticker.canonical(" vcb ") == "VCB")
    }

    @Test("A world index can only be served by its own feed, whatever the picker says")
    func inferredMarket() {
        #expect(Market.inferred(for: "DJI") == .world)
        #expect(Market.inferred(for: "IXIC") == .world)
        #expect(Market.inferred(for: "NI225") == .world)
        #expect(Market.inferred(for: "N225") == .world)
        // The three-letter DJI is the risky one — it has the shape of a HOSE ticker. Checked against the
        // Vietnamese board, which does not list it, before it was added here.
        #expect(Market.inferred(for: "VCB") == nil)
        #expect(Market.inferred(for: "BTCUSDT") == .crypto)
    }

    @Test("They are indices, so they are formatted and banded like one")
    func areIndices() {
        #expect(Ticker.isIndex("DJI"))
        #expect(Ticker.isIndex("IXIC"))
        #expect(Ticker.isIndex("NI225"))
    }

    @Test("Each index carries the venue whose clock it is on")
    func venues() {
        #expect(WorldIndex.listing(for: "DJI")?.exchange == .newYork)
        #expect(WorldIndex.listing(for: "IXIC")?.exchange == .newYork)
        #expect(WorldIndex.listing(for: "NI225")?.exchange == .tokyo)
        #expect(WorldIndex.listing(for: "VCB") == nil)
        // The panel's line under the ticker.
        #expect(WatchedSymbol(symbol: "DJI", market: .world, pinnedToMenuBar: false).venueLabel == "New York")
        #expect(WatchedSymbol(symbol: "NI225", market: .world, pinnedToMenuBar: false).venueLabel == "Tokyo")
    }

    @Test("No two listings claim the same spelling")
    func tableIsUnambiguous() {
        // A duplicate would make `listing(for:)` depend on the table's order, which nothing else does.
        let spellings = WorldIndex.all.flatMap { [$0.symbol] + $0.aliases }
        #expect(Set(spellings).count == spellings.count)
        // And no alias may be another index's canonical name.
        let canonical = Set(WorldIndex.all.map(\.symbol))
        #expect(WorldIndex.all.allSatisfy { listing in
            listing.aliases.allSatisfy { !canonical.contains($0) }
        })
    }
}
