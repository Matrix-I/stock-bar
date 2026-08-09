// Market.swift — which venue an instrument belongs to, and the two questions that can be answered
// from a ticker string alone.
//
// Split out of Quote.swift because both answers are load-bearing well outside the model: the market
// picks the data source, the refresh cadence, the price precision and the up/down colour convention,
// while `Ticker.isIndex` decides price scaling in VPSQuoteSource and decimal places in PriceFormat.

import Foundation

/// Which market an instrument trades on. Drives the refresh cadence (a closed exchange is not polled;
/// crypto is 24/7), the price formatting, and the up/down colour convention.
enum Market: String, Codable, Sendable, CaseIterable {
    /// Priced in dong, in Vietnam. The equities and indices on HOSE / HNX / UPCOM, and — since the gold gap
    /// needed them — the SJC bar and the dollar rate, which are on no exchange at all. So this is a bucket
    /// of venues rather than one, exactly as `.world` is: `DomesticIndex` carries which, and the session
    /// hours differ with it, because a jeweller does not keep a call auction or a lunch break.
    case vietnam
    /// Crypto pairs — always open.
    case crypto
    /// The world instruments in `WorldIndex.all` — Wall Street, Tokyo, gold and the dollar index. One
    /// market rather than one per country or asset class, because a market here selects a data source and
    /// a single feed serves all of them; the venue, which is what actually differs, is carried per symbol
    /// by the listing.
    case world
}

extension Market {
    /// The market's name where it has to share a line with something else — the Add field's verdict and the
    /// failure prefix under the panel. Short because both are read at a glance, next to the thing that
    /// matters more.
    var shortLabel: String {
        switch self {
        case .vietnam: return "VN"
        case .crypto:  return "Crypto"
        case .world:   return "World"
        }
    }

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
        // A named world instrument can only be served by one feed, and none of these names is a ticker on
        // the Vietnamese board — checked against it, including the three-letter DJI, DXY and XAU, before
        // adding them.
        if WorldIndex.listing(for: upper) != nil { return .world }
        // The domestic gold bar, the dollar rate and the gap between them. Named rather than guessed for
        // the same reason as the world rows, and the check that let them in was the same one: `USD` is a
        // live UPCOM ticker and `VND` is VNDirect on HOSE, so the obvious spellings had to be left out.
        if DomesticIndex.listing(for: upper) != nil { return .vietnam }
        return nil
    }
}

/// Facts about a ticker string that hold before any quote for it exists.
enum Ticker {
    /// Whether a symbol names an index rather than a tradable stock — or, for the one row in the world
    /// table that is a future rather than an index, something that behaves like one here: formatted with
    /// decimals, no ceiling/floor band, and no per-share fundamentals to look up. On the Vietnamese side it
    /// also picks the endpoint and the price scale, which is why one predicate is consulted by the feed,
    /// the formatter and the row.
    static func isIndex(_ symbol: String) -> Bool {
        let s = symbol.uppercased()
        if WorldIndex.listing(for: s) != nil { return true }
        return s.hasSuffix("INDEX") || s == "VN30" || s == "HNX30"
    }

    /// The spelling this app stores a typed symbol under: trimmed, upper-cased, and resolved to the
    /// canonical name where a venue and its readers disagree about one ("N225" and "^N225" are both the
    /// Nikkei this app calls NI225).
    ///
    /// Done once, at the front door, so the alias never reaches the watchlist: the id is "market:symbol",
    /// so two spellings of one index would otherwise be two rows quoting the same number.
    static func canonical(_ typed: String) -> String {
        let s = typed.trimmingCharacters(in: .whitespaces).uppercased()
        return WorldIndex.listing(for: s)?.symbol ?? DomesticIndex.listing(for: s)?.symbol ?? s
    }
}
