// MarketTests.swift — the two questions answered from a ticker string alone.
//
// `Market.inferred` exists because of a bug that was invisible for a whole release: BTCUSDT typed while
// the Add row's picker sat on its "VN" default was filed as a HOSE ticker, so the app asked a Vietnamese
// board for a symbol that does not exist there and the row showed a dash forever. The tests that matter
// most here are the NEGATIVE ones — the guess must stay narrow enough that it can never misfire in the
// opposite direction and file a real Vietnamese ticker under Binance.

import Testing
@testable import StockBarCore

@Suite("Market")
struct MarketTests {

    @Test("A stablecoin-quoted pair can only be crypto", arguments: [
        "BTCUSDT", "ETHUSDC", "SOLFDUSD", "XRPBUSD", "ADATUSD",
    ])
    func stablecoinPairsAreCrypto(symbol: String) {
        #expect(Market.inferred(for: symbol) == .crypto)
    }

    @Test("Case doesn't matter")
    func lowercaseIsInferredToo() {
        #expect(Market.inferred(for: "btcusdt") == .crypto)
    }

    @Test("A three-letter Vietnamese ticker says nothing, so the caller's choice stands", arguments: [
        "VCB", "FPT", "HPG", "VNINDEX", "VN30",
    ])
    func vietnameseTickersAreNotInferred(symbol: String) {
        #expect(Market.inferred(for: symbol) == nil)
    }

    @Test("Coin-quoted pairs are deliberately NOT inferred")
    func coinQuotedPairsAreLeftAlone() {
        // "BTC" and "BNB" are three characters, exactly like a HOSE ticker. Matching on them would risk
        // filing a Vietnamese equity under Binance — the same class of bug this inference exists to fix,
        // pointing the other way. So ETHBTC stays the caller's call.
        #expect(Market.inferred(for: "ETHBTC") == nil)
        #expect(Market.inferred(for: "SOLBNB") == nil)
    }

    @Test("A bare quote asset is not a pair")
    func bareQuoteAssetIsNotAPair() {
        // The suffix check requires the symbol to be LONGER than the quote asset; "USDT" alone is somebody
        // typing half a pair, not a market.
        #expect(Market.inferred(for: "USDT") == nil)
        #expect(Market.inferred(for: "USDC") == nil)
    }

    @Test("Index symbols are recognised by suffix and by name", arguments: [
        "VNINDEX", "HNXINDEX", "UPINDEX", "VN30", "HNX30", "vnindex",
    ])
    func indexSymbols(symbol: String) {
        #expect(Ticker.isIndex(symbol))
    }

    @Test("A tradable ticker is not an index", arguments: ["VCB", "FPT", "BTCUSDT", "VN100"])
    func nonIndexSymbols(symbol: String) {
        #expect(Ticker.isIndex(symbol) == false)
    }
}
