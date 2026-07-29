// Market.swift — which venue an instrument belongs to, and the two questions that can be answered
// from a ticker string alone.
//
// Split out of Quote.swift because both answers are load-bearing well outside the model: the market
// picks the data source, the refresh cadence, the price precision and the up/down colour convention,
// while `Ticker.isIndex` decides price scaling in VNQuoteSource and decimal places in PriceFormat.

import Foundation

/// Which market an instrument trades on. Drives the refresh cadence (a closed exchange is not polled;
/// crypto is 24/7), the price formatting, and the up/down colour convention.
enum Market: String, Codable, Sendable, CaseIterable {
    /// Vietnamese equities and indices (HOSE / HNX / UPCOM). Session hours in MarketHours.
    case vietnam
    /// Crypto pairs — always open.
    case crypto
}

extension Market {
    /// Quote assets a Binance pair can be denominated in that no Vietnamese ticker could ever end with.
    /// Deliberately only the stablecoins: they are all four characters or more, while a HOSE/HNX ticker
    /// is three letters and the indices are a handful of known names, so a suffix match here cannot
    /// misfire. Binance's coin-quoted pairs (ETHBTC, SOLBNB) are left out for exactly that reason — "BTC"
    /// is three characters and guessing on it risks filing a Vietnamese ticker under the wrong venue,
    /// which is the very bug this is here to fix.
    private static let cryptoQuoteAssets = ["USDT", "USDC", "FDUSD", "BUSD", "TUSD"]

    /// The market a symbol *must* belong to, judged from the ticker alone; nil when the ticker says
    /// nothing and the caller's own choice should stand.
    ///
    /// This exists because the two namespaces cannot overlap, and getting it wrong fails silently.
    /// Typing `BTCUSDT` while the Add row's picker sat on its "VN" default filed it as a HOSE ticker,
    /// so the app asked a Vietnamese board for a symbol that does not exist there: the row showed a
    /// dash forever, with no hint that the market — not the feed — was the problem.
    static func inferred(for symbol: String) -> Market? {
        let upper = symbol.uppercased()
        // `count >` and not `>=`: a bare quote asset typed on its own is not a pair.
        if cryptoQuoteAssets.contains(where: { upper.hasSuffix($0) && upper.count > $0.count }) {
            return .crypto
        }
        return nil
    }
}

/// Facts about a ticker string that hold before any quote for it exists.
enum Ticker {
    /// Whether a symbol names an index rather than a tradable stock. Indices are formatted with decimals,
    /// have no ceiling/floor band, and come from a different VPS endpoint on a different price scale — so
    /// this one predicate is consulted by the feed, the formatter and the row.
    static func isIndex(_ symbol: String) -> Bool {
        let s = symbol.uppercased()
        return s.hasSuffix("INDEX") || s == "VN30" || s == "HNX30"
    }
}
