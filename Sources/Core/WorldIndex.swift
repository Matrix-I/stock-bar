// WorldIndex.swift — the world instruments this app carries, in one table.
//
// A table rather than a special case per row spread through the tree, because a single instrument is
// spelled four different ways by the time it reaches the screen: the user types `DJI`, the feed wants
// `^DJI`, the hours that decide when it is worth polling belong to New York, and the panel wants a venue
// line under the ticker. Adding one is a row here plus, if it trades somewhere new, one window in
// MarketHours.
//
// Four of the five rows are indices; GOLD is not, and the type name is the looser for it. It is COMEX's
// front-month gold future, because SPOT gold is not on this feed at all — `XAUUSD=X`, `XAU=X` and
// `GCUSD=X` all answer 404, checked on 2026-08-07. The future trades at a basis over spot (a few tens of
// dollars, and it widens with the contract), so the number is not the "giá vàng thế giới" of a spot page
// to the dollar. That is precisely why the venue line says COMEX: it names which gold price this is.
//
// The set is deliberately small and explicit. WorldQuoteSource will forward any symbol Yahoo recognises,
// so nothing here rejects an unlisted one — but a symbol outside this table has no venue, which means the
// session gate can only guess at its hours, so it is not something to advertise.

import Foundation

/// The venues behind the world instruments. Kept separate from `Market` because `Market` picks the data
/// source and there is one source for all of them: what differs is the trading day, and only MarketHours
/// cares.
enum WorldExchange: String, Sendable, CaseIterable {
    case newYork
    case tokyo
    /// CME's metals floor, which quotes the gold future nearly around the clock.
    case comex
    /// ICE Futures US, which computes the dollar index and keeps the same overnight week as COMEX.
    case iceUS

    /// The line shown under the ticker in the panel. The venue rather than the instrument's own name ("Dow
    /// Jones", "Gold"), for the same reason the VN rows say HOSE: when a price hasn't moved for hours, the
    /// useful thing to know is which clock it is on — and for GOLD it also answers *which* gold price,
    /// since a COMEX future and a spot page do not print the same number.
    var label: String {
        switch self {
        case .newYork: return "New York"
        case .tokyo:   return "Tokyo"
        case .comex:   return "COMEX"
        case .iceUS:   return "ICE"
        }
    }

    /// How far behind real time this venue's free data is, and therefore how old a healthy quote from it
    /// looks. Added to the staleness allowance; without it a perfectly working row greys out and stays that
    /// way, which is the single most misleading thing this app can do.
    ///
    /// Measured against the live endpoint on 2026-08-07: the equity indices answer within seconds (^DJI 0.9s,
    /// ^IXIC 4.4s), while `GC=F` and `DX-Y.NYB` were both a shade over 600 seconds behind. That is not a slow
    /// feed but the exchange's own rule — CME and ICE mandate a ten-minute delay on data nobody pays for, and
    /// Yahoo does not report it in `exchangeDataDelayedBy`, which comes back null for every symbol here.
    ///
    /// Rounded UP to fifteen minutes rather than set to the measured ten. The feed publishes minute bars, so
    /// the true lag sweeps between 600 and 660 seconds, and the app only polls once a minute on top of that —
    /// an allowance pinned near the measurement would let a healthy row flicker grey in the seconds before
    /// each poll. The looser bound costs little, because with data this old "stale" can only usefully mean
    /// "the feed has stopped", never "this isn't the latest tick".
    var feedDelay: TimeInterval {
        switch self {
        case .newYork, .tokyo: return 0
        case .comex, .iceUS:   return 15 * 60
        }
    }
}

/// One world instrument, as this app knows it.
struct WorldIndex: Sendable, Equatable {
    /// What the user types, and what the watchlist stores.
    let symbol: String
    /// Yahoo's own spelling. Indices carry a caret there and the other instruments carry `=`, `-` or `.`,
    /// all of which are awkward to type and easy to lose to a shell or a URL, so none of it leaves this
    /// file's neighbourhood. WorldQuoteSource percent-encodes the lot; `GC%3DF` and `DX%2DY%2ENYB` were
    /// both checked against the live endpoint before they were listed here.
    let yahoo: String
    let exchange: WorldExchange
    /// Other spellings accepted at the Add field, resolved to `symbol` before anything is stored. Only
    /// unambiguous ones: `DOW` is missing on purpose, because it is a real NYSE ticker (Dow Inc.) and
    /// would quietly answer a question nobody asked. `GC` and `DX` are missing for a weaker version of
    /// the same reason — two letters is short enough that a future Vietnamese listing could claim one,
    /// and the full Yahoo spelling is already accepted for anyone who thinks in it.
    let aliases: [String]
}

extension WorldIndex {

    /// The advertised set. Every symbol and alias here was checked against the VPS board before it was
    /// added — `getliststockdata/GOLD,DXY,XAU,GC,DX` answers `[]`, so none of them can shadow a
    /// Vietnamese ticker, which is the collision that files a row under a venue that has never heard of
    /// it and leaves it on a dash for good.
    static let all: [WorldIndex] = [
        WorldIndex(symbol: "DJI", yahoo: "^DJI", exchange: .newYork, aliases: ["^DJI", "DJIA"]),
        WorldIndex(symbol: "IXIC", yahoo: "^IXIC", exchange: .newYork, aliases: ["^IXIC", "NASDAQ"]),
        WorldIndex(symbol: "NI225", yahoo: "^N225", exchange: .tokyo, aliases: ["^N225", "N225", "NIKKEI"]),
        // Gold, and the one row that is not an index — see the file header for why a future stands in for
        // spot. XAU is the metal's own ISO code, which is what a trader is as likely to type as "GOLD".
        WorldIndex(symbol: "GOLD", yahoo: "GC=F", exchange: .comex, aliases: ["GC=F", "XAU", "XAUUSD"]),
        // The dollar index — an index proper, computed by ICE against a basket of six currencies, and the
        // one number that answers "is the dollar strong today" without naming a pair.
        WorldIndex(symbol: "DXY", yahoo: "DX-Y.NYB", exchange: .iceUS, aliases: ["DX-Y.NYB", "USDX"]),
    ]

    /// The listing for a typed or stored symbol, by canonical name or by alias. nil for everything else,
    /// including every Vietnamese ticker and crypto pair.
    static func listing(for symbol: String) -> WorldIndex? {
        let s = symbol.trimmingCharacters(in: .whitespaces).uppercased()
        return all.first { $0.symbol == s || $0.aliases.contains(s) }
    }

    /// The symbol to ask Yahoo for. Falls through unchanged for anything not in the table, which is what
    /// lets someone who knows Yahoo's spelling watch a symbol this app has never heard of.
    static func yahooSymbol(for symbol: String) -> String {
        listing(for: symbol)?.yahoo ?? symbol.trimmingCharacters(in: .whitespaces).uppercased()
    }

    /// How old a healthy quote for `symbol` looks — see `WorldExchange.feedDelay`. Zero for everything not
    /// in the table, which covers every Vietnamese ticker and crypto pair as well as an unlisted world
    /// symbol: nothing is known about the latter's feed, and assuming it is prompt errs towards a row that
    /// greys out rather than one that lies about being current.
    static func feedDelay(for symbol: String) -> TimeInterval {
        listing(for: symbol)?.exchange.feedDelay ?? 0
    }
}
