// WatchedSymbolTests.swift — identity and the two labels a watched row is rendered with.
//
// The identity matters beyond equality: it is the key the whole quote cache and the sparkline history are
// stored under, so a change to its shape silently orphans every stored quote.

import Testing
@testable import StockBarCore

@Suite("WatchedSymbol")
struct WatchedSymbolTests {

    private func entry(_ symbol: String, _ market: Market) -> WatchedSymbol {
        WatchedSymbol(symbol: symbol, market: market, pinnedToMenuBar: false)
    }

    @Test("Identity is market AND symbol, because the two namespaces can collide")
    func identityIncludesMarket() {
        #expect(entry("BTCUSDT", .crypto).id == "crypto:BTCUSDT")
        #expect(entry("BTCUSDT", .vietnam).id != entry("BTCUSDT", .crypto).id)
    }

    @Test("Long tickers get a menu-bar alias", arguments: [
        ("VNINDEX", "VNI"),      // the only ticker too long to sit beside anything else
        ("HNXINDEX", "HNX"),
        ("VN30", "VN30"),        // already short enough
        ("VCB", "VCB"),
    ])
    func vietnameseMenuBarLabels(symbol: String, expected: String) {
        #expect(entry(symbol, .vietnam).menuBarLabel == expected)
    }

    @Test("A crypto pair is shown by its base asset", arguments: [
        ("BTCUSDT", "BTC"), ("ETHUSDT", "ETH"), ("SOLUSDT", "SOL"), ("BNBUSDT", "BNB"),
    ])
    func cryptoMenuBarLabels(symbol: String, expected: String) {
        // The menu bar has room for the base asset and USDT is the only quote currency the app requests,
        // so the suffix is dropped rather than shown.
        #expect(entry(symbol, .crypto).menuBarLabel == expected)
    }

    @Test("The venue line distinguishes an index from an equity")
    func venueLabels() {
        #expect(entry("VCB", .vietnam).venueLabel == "HOSE")
        #expect(entry("VNINDEX", .vietnam).venueLabel == "Index")
        #expect(entry("BTCUSDT", .crypto).venueLabel == "Binance")
    }
}
