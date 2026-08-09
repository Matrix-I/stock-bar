// PortfolioTests.swift — the first thing in this app that adds two rows together, and the ways that lies.
//
// A wrong total is more confidently wrong than any row it is made of: it renders as one clean number with
// nothing beside it to check against. Every test here is therefore about a refusal — a currency with no
// rate, a rate that hasn't arrived, a basis of zero — rather than about the multiplication, which is the
// part that cannot silently be wrong.

import Testing
import Foundation
@testable import StockBarCore

@Suite("Portfolio")
struct PortfolioTests {

    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func held(_ symbol: String, _ market: Market, qty: Double, cost: Double) -> WatchedSymbol {
        WatchedSymbol(symbol: symbol, market: market, pinnedToMenuBar: false,
                      holding: Holding(quantity: qty, averageCost: cost))
    }

    private func quote(_ symbol: String, _ market: Market, _ price: Double,
                       at date: Date? = nil) -> (String, Quote) {
        let entry = WatchedSymbol(symbol: symbol, market: market, pinnedToMenuBar: false)
        return (entry.id, Quote(symbol: symbol, market: market, price: price, reference: nil,
                                ceiling: nil, floor: nil, volume: nil, asOf: date ?? now))
    }

    @Test("Every row's currency is named, and the Nikkei's is not the dollar")
    func currencies() {
        #expect(Currency.of(symbol: "VCB", market: .vietnam) == .vnd)
        #expect(Currency.of(symbol: "SJC", market: .vietnam) == .vnd)
        #expect(Currency.of(symbol: "GOLDGAP", market: .vietnam) == .vnd)
        #expect(Currency.of(symbol: "BTCUSDT", market: .crypto) == .usd)
        #expect(Currency.of(symbol: "GOLD", market: .world) == .usd)
        #expect(Currency.of(symbol: "DJI", market: .world) == .usd)
        // The whole reason this type exists: ~61,000 yen looks like a dollar figure and is not one, and
        // folding it in as dollars would be out by a factor of 150 while still rendering plausibly.
        #expect(Currency.of(symbol: "NI225", market: .world) == .jpy)
        // An unlisted world symbol falls back to dollars, which is what that feed quotes.
        #expect(Currency.of(symbol: "AAPL", market: .world) == .usd)
    }

    @Test("Dong and dollars add up through the panel's own USDVND")
    func convertsThroughTheVisibleRate() throws {
        let entries = [
            held("VCB", .vietnam, qty: 1_200, cost: 58_400),     // 71,640,000 VND at 59,700
            held("BTCUSDT", .crypto, qty: 0.5, cost: 60_000),    // 32,000 USD at 64,000
        ]
        let quotes = Dictionary(uniqueKeysWithValues: [
            quote("VCB", .vietnam, 59_700),
            quote("BTCUSDT", .crypto, 64_000),
            quote("USDVND", .vietnam, 25_000),
        ])
        let total = try #require(Portfolio.total(for: entries, quotes: quotes))

        // 71,640,000 + 32,000 × 25,000 = 871,640,000
        #expect(total.value == 871_640_000)
        // Cost converts at the SAME rate, so the percentage is the instruments' own move expressed in
        // dong rather than a currency gain nobody made — see the file header.
        #expect(total.cost == 70_080_000 + 30_000 * 25_000)
        #expect(total.excluded == 0)
        // 1,560,000 dong on the VCB, plus 0.5 × (64,000 − 60,000) × 25,000 = 50,000,000 on the BTC.
        #expect(abs(total.profit - 51_560_000) < 1)
        // Against a basis of 820,080,000 that is 6.29% — the instruments' own move, since both sides of
        // the division converted at the same rate.
        #expect(abs(try #require(total.profitPercent) - 6.2872) < 0.001)
    }

    @Test("A currency with no rate is left out and counted, never guessed at")
    func excludesTheUnconvertible() throws {
        let entries = [
            held("VCB", .vietnam, qty: 1_000, cost: 50_000),
            held("NI225", .world, qty: 10, cost: 60_000),   // yen — no rate exists in this app
        ]
        let quotes = Dictionary(uniqueKeysWithValues: [
            quote("VCB", .vietnam, 60_000),
            quote("NI225", .world, 61_000),
            quote("USDVND", .vietnam, 25_000),
        ])
        let total = try #require(Portfolio.total(for: entries, quotes: quotes))
        // Only the dong row. Folding the yen in at the dollar rate would read 15,310,000,000 — a number
        // with no tell whatsoever that it is 150 times too large.
        #expect(total.value == 60_000_000)
        #expect(total.excluded == 1)
    }

    @Test("Without USDVND the dong still totals and the dollars are reported missing")
    func rateNotYetArrived() throws {
        let entries = [
            held("VCB", .vietnam, qty: 1_000, cost: 50_000),
            held("BTCUSDT", .crypto, qty: 1, cost: 60_000),
        ]
        let quotes = Dictionary(uniqueKeysWithValues: [
            quote("VCB", .vietnam, 60_000),
            quote("BTCUSDT", .crypto, 64_000),
        ])
        let total = try #require(Portfolio.total(for: entries, quotes: quotes))
        #expect(total.value == 60_000_000)
        #expect(total.excluded == 1)

        // A rate quoted at zero is not a rate. Treating it as one would multiply every dollar holding
        // into nothing and quietly shrink the total.
        var withZero = quotes
        withZero["vietnam:USDVND"] = Quote(symbol: "USDVND", market: .vietnam, price: 0, reference: nil,
                                           ceiling: nil, floor: nil, volume: nil, asOf: now)
        #expect(Portfolio.total(for: entries, quotes: withZero)?.excluded == 1)
    }

    @Test("The total is as old as its stalest ingredient, the rate included")
    func asOfIsTheOldestInput() throws {
        let saturday = now.addingTimeInterval(-36 * 3600)
        let entries = [held("SJC", .vietnam, qty: 2, cost: 140_000_000),
                       held("BTCUSDT", .crypto, qty: 1, cost: 60_000)]
        var quotes = Dictionary(uniqueKeysWithValues: [
            quote("SJC", .vietnam, 144_000_000, at: saturday),
            quote("BTCUSDT", .crypto, 64_000),
            quote("USDVND", .vietnam, 25_000),
        ])
        #expect(try #require(Portfolio.total(for: entries, quotes: quotes)).asOf == saturday)

        // The rate bounds it too: a crypto tick from a second ago converted through Friday's sheet is a
        // Friday number, however fresh the tick was.
        quotes["vietnam:SJC"] = nil
        quotes["vietnam:USDVND"] = Quote(symbol: "USDVND", market: .vietnam, price: 25_000, reference: nil,
                                         ceiling: nil, floor: nil, volume: nil, asOf: saturday)
        #expect(try #require(Portfolio.total(for: [entries[1]], quotes: quotes)).asOf == saturday)
    }

    @Test("Nothing held is no total at all, not a total of zero")
    func nothingHeld() {
        let watched = [WatchedSymbol(symbol: "VCB", market: .vietnam, pinnedToMenuBar: false)]
        let quotes = Dictionary(uniqueKeysWithValues: [quote("VCB", .vietnam, 60_000)])
        // A zero would claim the user owns nothing; the truth is that nobody has said. The panel draws
        // no line at all for nil, and would draw "0" for a zero.
        #expect(Portfolio.total(for: watched, quotes: quotes) == nil)

        // A position with no quote yet cannot be valued, so it does not become a total either.
        let unquoted = [held("VCB", .vietnam, qty: 100, cost: 50_000)]
        #expect(Portfolio.total(for: unquoted, quotes: [:]) == nil)

        // A cost of zero is a real state — size known, cost not yet typed — so it totals a value and
        // refuses a percentage, exactly as a single Holding does.
        let noCost = [held("VCB", .vietnam, qty: 100, cost: 0)]
        let partial = Portfolio.total(for: noCost, quotes: quotes)
        #expect(partial?.value == 6_000_000)
        #expect(partial?.profitPercent == nil)
    }
}
