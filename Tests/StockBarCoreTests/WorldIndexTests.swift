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

    @Test("Every listing maps to the spelling its own feed wants")
    func feedSpelling() {
        #expect(WorldIndex.feedSymbol(for: "DJI") == "^DJI")
        #expect(WorldIndex.feedSymbol(for: "IXIC") == "^IXIC")
        // The one where the two spellings differ by more than a caret: the app's NI225 is Yahoo's ^N225.
        #expect(WorldIndex.feedSymbol(for: "NI225") == "^N225")
        // The dollar index carries no caret but plenty else — `-` and `.` — and gold is on another feed
        // entirely, with a colon in its name. All of it is percent-encoded by whichever source gets it, and
        // nothing outside this table should ever have to know any of it.
        #expect(WorldIndex.feedSymbol(for: "DXY") == "DX-Y.NYB")
        #expect(WorldIndex.feedSymbol(for: "GOLD") == "TVC:GOLD")
        // Anything not in the table is forwarded as typed, which is what lets a Yahoo symbol this app has
        // never heard of still be watched.
        #expect(WorldIndex.feedSymbol(for: "aapl") == "AAPL")
    }

    @Test("Gold comes from TradingView and everything else from Yahoo")
    func feedRouting() {
        // Spot XAU/USD is on no Yahoo spelling at all, and the COMEX future Yahoo does carry prints some
        // sixty dollars above it. So this row alone takes the second feed — and getting the routing wrong
        // is silent: the wrong upstream either 404s or answers with a plausible number for another market.
        #expect(WorldIndex.feed(for: "GOLD") == .tradingView)
        #expect(WorldIndex.feed(for: "XAU") == .tradingView)      // via the alias, like every other lookup
        #expect(WorldIndex.feed(for: "DXY") == .yahoo)
        #expect(WorldIndex.feed(for: "DJI") == .yahoo)
        // An unlisted symbol goes to Yahoo, which is the feed that will take an arbitrary one. TradingView's
        // scanner wants an EXCHANGE:SYMBOL pair, so guessing it would turn "not listed" into a wrong 404.
        #expect(WorldIndex.feed(for: "AAPL") == .yahoo)
    }

    @Test("Aliases resolve to one canonical spelling before anything is stored")
    func aliases() {
        #expect(Ticker.canonical("n225") == "NI225")
        #expect(Ticker.canonical("^N225") == "NI225")
        #expect(Ticker.canonical(" djia ") == "DJI")
        #expect(Ticker.canonical("nasdaq") == "IXIC")
        // Gold answers to the metal's ISO code and to the feed's own futures spelling, so the three ways of
        // asking for it cannot become three rows quoting the same contract.
        #expect(Ticker.canonical("xau") == "GOLD")
        #expect(Ticker.canonical("XAUUSD") == "GOLD")
        #expect(Ticker.canonical("gc=f") == "GOLD")   // the future by name still means the gold row
        #expect(Ticker.canonical("usdx") == "DXY")
        #expect(Ticker.canonical("dx-y.nyb") == "DXY")
        // Not aliases: DOW is a real NYSE ticker (Dow Inc.), and GC/DX are short enough that a Vietnamese
        // listing could yet claim them. Treating either as ours would answer a question nobody asked.
        #expect(Ticker.canonical("DOW") == "DOW")
        #expect(Ticker.canonical("GC") == "GC")
        #expect(Ticker.canonical("DX") == "DX")
        // Everything else is left alone beyond trimming and upper-casing.
        #expect(Ticker.canonical(" vcb ") == "VCB")
    }

    @Test("A world instrument can only be served by its own feed, whatever the picker says")
    func inferredMarket() {
        #expect(Market.inferred(for: "DJI") == .world)
        #expect(Market.inferred(for: "IXIC") == .world)
        #expect(Market.inferred(for: "NI225") == .world)
        #expect(Market.inferred(for: "N225") == .world)
        #expect(Market.inferred(for: "GOLD") == .world)
        #expect(Market.inferred(for: "XAU") == .world)
        #expect(Market.inferred(for: "DXY") == .world)
        // The three-letter ones are the risky ones — they have the shape of a HOSE ticker. Checked against
        // the Vietnamese board, which lists none of them, before they were added here.
        #expect(Market.inferred(for: "VCB") == nil)
        #expect(Market.inferred(for: "BTCUSDT") == .crypto)
    }

    @Test("They are formatted and banded like indices, the commodity included")
    func areIndices() {
        #expect(Ticker.isIndex("DJI"))
        #expect(Ticker.isIndex("IXIC"))
        #expect(Ticker.isIndex("NI225"))
        #expect(Ticker.isIndex("DXY"))
        // GOLD is a commodity price, not an index. It still answers true, and that is the intended reading
        // of the predicate here: decimals in the price, no ceiling/floor band, no per-share fundamentals to
        // fetch. Excluding it would print the gold price as a bare integer.
        #expect(Ticker.isIndex("GOLD"))
    }

    @Test("Each listing carries the venue whose clock it is on")
    func venues() {
        #expect(WorldIndex.listing(for: "DJI")?.exchange == .newYork)
        #expect(WorldIndex.listing(for: "IXIC")?.exchange == .newYork)
        #expect(WorldIndex.listing(for: "NI225")?.exchange == .tokyo)
        #expect(WorldIndex.listing(for: "GOLD")?.exchange == .spot)
        #expect(WorldIndex.listing(for: "DXY")?.exchange == .iceUS)
        #expect(WorldIndex.listing(for: "VCB") == nil)
        // The panel's line under the ticker.
        #expect(WatchedSymbol(symbol: "DJI", market: .world, pinnedToMenuBar: false).venueLabel == "New York")
        #expect(WatchedSymbol(symbol: "NI225", market: .world, pinnedToMenuBar: false).venueLabel == "Tokyo")
        // For gold this line is doing more than naming a clock: it says the number is the OTC spot price,
        // not the COMEX future sixty dollars above it that Yahoo would have handed over.
        #expect(WatchedSymbol(symbol: "GOLD", market: .world, pinnedToMenuBar: false).venueLabel == "Spot")
        #expect(WatchedSymbol(symbol: "DXY", market: .world, pinnedToMenuBar: false).venueLabel == "ICE")
    }

    @Test("A venue that holds its data back says so, so a healthy row is not called stale")
    func feedDelay() {
        // ICE publishes free data ten minutes late, which is not a fault to report but a rule to account
        // for: measured at 602s behind on 2026-08-07, against 0.9s for ^DJI. Without an allowance the
        // dollar-index row rendered dimmed the whole time its venue was trading.
        #expect(WorldIndex.feedDelay(for: "DXY") == 15 * 60)
        // Gold is on a streaming feed and keeps the tight allowance — which is also what a wrong routing
        // would show up as, since a delayed row judged against it dims and stays dimmed.
        #expect(WorldIndex.feedDelay(for: "GOLD") == 0)
        #expect(WorldIndex.feedDelay(for: "XAU") == 0)            // via the alias, like every other lookup
        // The equity indices answer in seconds too, so they keep it as well — that is what lets a Dow row
        // still report a feed that has actually stopped.
        #expect(WorldIndex.feedDelay(for: "DJI") == 0)
        #expect(WorldIndex.feedDelay(for: "IXIC") == 0)
        #expect(WorldIndex.feedDelay(for: "NI225") == 0)
        // And nothing outside the table gets an allowance it hasn't earned.
        #expect(WorldIndex.feedDelay(for: "VCB") == 0)
        #expect(WorldIndex.feedDelay(for: "AAPL") == 0)
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
