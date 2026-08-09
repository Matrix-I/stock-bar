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
                       at date: Date? = nil, currency: Currency? = nil) -> (String, Quote) {
        let entry = WatchedSymbol(symbol: symbol, market: market, pinnedToMenuBar: false)
        return (entry.id, Quote(symbol: symbol, market: market, price: price, reference: nil,
                                ceiling: nil, floor: nil, volume: nil, asOf: date ?? now,
                                currency: currency))
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
    }

    @Test("A ticker this app cannot read the unit off is not quietly called dollars")
    func declinesToGuess() {
        // `.world` is a bucket served by Yahoo, which forwards any ticker it knows and prices each listing
        // in that listing's own currency. Defaulting the unlisted case to USD is how the yen error this
        // type exists to prevent got back in through the front door: 7203.T is Toyota at ~2,980 JPY.
        #expect(Currency.of(symbol: "7203.T", market: .world) == nil)
        #expect(Currency.of(symbol: "AAPL", market: .world) == nil)
        // Coin-quoted crypto is the same shape of error at a different scale — ETHBTC prints in bitcoin,
        // so 0.03 is three-hundredths of a coin and not three cents.
        #expect(Currency.of(symbol: "ETHBTC", market: .crypto) == nil)
        #expect(Currency.of(symbol: "ETHUSDC", market: .crypto) == .usd)
    }

    @Test("A feed that names its own currency is believed, including when it says something unusable")
    func feedNamesTheUnit() {
        #expect(Currency(feedCode: "USD") == .usd)
        #expect(Currency(feedCode: "JPY") == .jpy)
        #expect(Currency(feedCode: " vnd ") == .vnd)
        // No rate for these, so "unusable" and "unstated" collapse to one answer and one branch.
        #expect(Currency(feedCode: "EUR") == nil)
        #expect(Currency(feedCode: "") == nil)
    }

    @Test("The feed's own currency decides an unlisted world row, and the table never has to guess")
    func unlistedWorldRowUsesTheFeedsAnswer() throws {
        let entries = [held("AAPL", .world, qty: 100, cost: 200),
                       held("7203.T", .world, qty: 100, cost: 2_000)]
        let quotes = Dictionary(uniqueKeysWithValues: [
            quote("AAPL", .world, 313, currency: .usd),
            quote("7203.T", .world, 2_980, currency: .jpy),
            quote("USDVND", .vietnam, 25_000),
        ])
        let total = try #require(Portfolio.total(for: entries, quotes: quotes))
        // Apple converts; Toyota is named as yen by the response its price arrived in, and is excluded.
        // Counting it as dollars would have added 7,450,000,000 VND to a 783,250,000 portfolio.
        #expect(total.value == 100 * 313 * 25_000)
        #expect(total.excluded == 1)

        // And with no word from the feed there is nothing left to go on, so it is excluded rather than
        // assumed — the table has never heard of either symbol.
        let silent = Dictionary(uniqueKeysWithValues: [
            quote("AAPL", .world, 313),
            quote("USDVND", .vietnam, 25_000),
        ])
        #expect(Portfolio.total(for: [entries[0]], quotes: silent) == nil)
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

    @Test("A position with no cost is worth something and has made nothing measurable")
    func costlessPositionStaysOutOfTheReturn() throws {
        // The case the test above could not see, because there every position lacked a basis and the
        // `cost > 0` guard covered for it. MIX one basis-less row with one real one and the guard stops
        // firing: the whole 144,000,000 landed in `profit` and the panel drew ▲ +308.00% in green on a
        // portfolio that had made ten million.
        let entries = [held("VCB", .vietnam, qty: 1_000, cost: 50_000),
                       held("SJC", .vietnam, qty: 1, cost: 0)]
        let quotes = Dictionary(uniqueKeysWithValues: [
            quote("VCB", .vietnam, 60_000),
            quote("SJC", .vietnam, 144_000_000),
        ])
        let total = try #require(Portfolio.total(for: entries, quotes: quotes))

        // Both are owned, so both are worth something and both are in the total.
        #expect(total.value == 204_000_000)
        #expect(total.excluded == 0)
        // Only one of them can be judged, so only one is in the return — the truth the app already knew
        // one level down, where Holding.profit returns nil for exactly this position.
        #expect(total.measured == 60_000_000)
        #expect(total.cost == 50_000_000)
        #expect(total.profit == 10_000_000)
        #expect(abs(try #require(total.profitPercent) - 20) < 0.001)
        // And it says so, because a percentage covering part of a portfolio without a word looks exactly
        // like one covering all of it.
        #expect(total.withoutBasis == 1)

        // The same portfolio in the other order is the same portfolio. Worth pinning because the two
        // accumulators are stepped inside one loop, and a version that assigned `measured` from the running
        // `value` instead of adding to it agreed with this test exactly as long as the basis-less row
        // happened to come last — which is a property of the watchlist, not of the arithmetic.
        let reversed = try #require(Portfolio.total(for: entries.reversed(), quotes: quotes))
        #expect(reversed.value == total.value)
        #expect(reversed.measured == total.measured)
        #expect(reversed.profit == total.profit)
    }

    @Test("A held row whose price has not arrived is counted, not quietly dropped")
    func unpricedPositionIsCounted() throws {
        let entries = [held("VCB", .vietnam, qty: 1_000, cost: 50_000),
                       held("FPT", .vietnam, qty: 500, cost: 100_000)]
        // FPT's quote is missing — a feed failing, or a symbol nobody answers for. The total is short by a
        // real position, and silence would present the remainder as the whole.
        let quotes = Dictionary(uniqueKeysWithValues: [quote("VCB", .vietnam, 60_000)])
        let total = try #require(Portfolio.total(for: entries, quotes: quotes))
        #expect(total.value == 60_000_000)
        #expect(total.unpriced == 1)
        #expect(total.excluded == 0)
        #expect(total.withoutBasis == 0)
    }
}
