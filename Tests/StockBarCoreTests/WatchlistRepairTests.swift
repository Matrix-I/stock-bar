// WatchlistRepairTests.swift — the self-healing load.
//
// This is the regression test for the bug that motivated extracting the function at all: three crypto
// pairs sat in a real watchlist filed as Vietnamese equities, so the app asked a HOSE backend about them
// and every row showed a dash. It was only diagnosable by decoding the preferences plist by hand.
//
// The "no change means no change" test is load-bearing in a way that isn't obvious: Watchlist writes the
// repaired list back to UserDefaults only when it differs from what it read, so an equality that
// accidentally became false would make every launch perform a write.

import Testing
@testable import StockBarCore

@Suite("WatchlistRepair")
struct WatchlistRepairTests {

    @Test("A crypto pair filed as a Vietnamese equity is refiled")
    func refilesMisfiledCryptoPair() {
        let stored = [WatchedSymbol(symbol: "BTCUSDT", market: .vietnam, pinnedToMenuBar: true)]
        let repaired = WatchlistRepair.repaired(stored)
        #expect(repaired.count == 1)
        #expect(repaired[0].market == .crypto)
        #expect(repaired[0].symbol == "BTCUSDT")
        // The pin is a user choice and survives the correction — silently unpinning a row would look like
        // a second bug.
        #expect(repaired[0].pinnedToMenuBar)
    }

    @Test("A correct list comes back equal, so the caller performs no write")
    func correctListIsUnchanged() {
        let stored = [
            WatchedSymbol(symbol: "VNINDEX", market: .vietnam, pinnedToMenuBar: true),
            WatchedSymbol(symbol: "VCB", market: .vietnam, pinnedToMenuBar: false),
            WatchedSymbol(symbol: "BTCUSDT", market: .crypto, pinnedToMenuBar: true),
        ]
        #expect(WatchlistRepair.repaired(stored) == stored)
    }

    @Test("A ticker the inference has no opinion on keeps whatever market it was stored under")
    func ambiguousTickerIsLeftAlone() {
        // Only the stablecoin suffixes are decisive. A three-letter ticker stored as crypto is a choice
        // this function is not entitled to overrule — see Market.inferred.
        let stored = [WatchedSymbol(symbol: "ETHBTC", market: .crypto, pinnedToMenuBar: false)]
        #expect(WatchlistRepair.repaired(stored)[0].market == .crypto)
    }

    @Test("A repair that collides with an existing row keeps the first")
    func repairCanCollide() {
        // The id is "market:symbol", so refiling BTCUSDT from vietnam to crypto can land on an id already
        // in the list. Without the dedup the list would hold two rows with the same id, which is a
        // duplicate-key crash waiting in any ForEach over it.
        let stored = [
            WatchedSymbol(symbol: "BTCUSDT", market: .crypto, pinnedToMenuBar: true),
            WatchedSymbol(symbol: "BTCUSDT", market: .vietnam, pinnedToMenuBar: false),
        ]
        let repaired = WatchlistRepair.repaired(stored)
        #expect(repaired.count == 1)
        #expect(repaired[0].pinnedToMenuBar)   // the first one, pin intact
    }

    @Test("Order is preserved — it is what decides which pinned symbols get a menu-bar slot")
    func orderIsPreserved() {
        let stored = [
            WatchedSymbol(symbol: "VCB", market: .vietnam, pinnedToMenuBar: false),
            WatchedSymbol(symbol: "ETHUSDT", market: .vietnam, pinnedToMenuBar: false),
            WatchedSymbol(symbol: "VNINDEX", market: .vietnam, pinnedToMenuBar: true),
        ]
        #expect(WatchlistRepair.repaired(stored).map(\.symbol) == ["VCB", "ETHUSDT", "VNINDEX"])
    }

    @Test("An empty list repairs to an empty list rather than to the defaults")
    func emptyStaysEmpty() {
        // Falling back to the shipped defaults is Watchlist's decision, made from a failed decode — not
        // something this function should do behind its back.
        #expect(WatchlistRepair.repaired([]).isEmpty)
    }
}
