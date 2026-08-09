// WorldIndex.swift — the world instruments this app carries, in one table.
//
// A table rather than a special case per row spread through the tree, because a single instrument is
// spelled four different ways by the time it reaches the screen: the user types `DJI`, the feed wants
// `^DJI`, the hours that decide when it is worth polling belong to New York, and the panel wants a venue
// line under the ticker. Adding one is a row here plus, if it trades somewhere new, one window in
// MarketHours.
//
// Four of the five rows are indices; GOLD is not, and the type name is the looser for it. It is the OTC
// spot price of the metal, XAU/USD, which is the number a Vietnamese "giá vàng thế giới" page quotes and
// the one TradingView draws as GOLD. It took a second feed to get: Yahoo carries no spot gold at all
// (`XAUUSD=X`, `XAU=X` and `GCUSD=X` all answer 404, checked 2026-08-07), and the COMEX front-month future
// it does carry trades some sixty dollars above spot on the cost of carry — right for a futures trader,
// wrong for someone comparing against a gold page.
//
// So a listing names its FEED as well as its venue, and that is the whole reason `WorldFeed` exists. It
// then names a second one, because the feed with the right price turned out not to publish bars at all:
// `WorldBars` is where a row says who draws its sparkline when that is somebody else.
//
// The set is deliberately small and explicit. The Yahoo source will forward any symbol it recognises, so
// nothing here rejects an unlisted one — but a symbol outside this table has no venue, which means the
// session gate can only guess at its hours, so it is not something to advertise.

import Foundation

/// Which backend answers for a listing. The world bucket is one `Market` but no longer one upstream:
/// Yahoo's chart endpoint serves the indices, and TradingView's scanner serves spot gold because nothing
/// on Yahoo does. Kept off `WorldExchange` on purpose — a venue is where an instrument trades and a feed is
/// who we ask about it, and those two came apart the moment spot needed a different upstream.
enum WorldFeed: String, Sendable, CaseIterable {
    case yahoo
    case tradingView
}

/// Where a row's sparkline comes from, which is usually but not always the feed that has its price.
///
/// A separate axis from `WorldFeed` because a feed answering "what is it worth now" and a feed answering
/// "what has it done today" are separate capabilities, and on spot gold they came apart: TradingView's
/// scanner has the best price and publishes no series at all, so the bars have to be asked of somebody
/// else. Modelled as a case with the foreign spelling attached rather than as another `WorldFeed` value,
/// so that a bars-only upstream can never be routed a price request — there is no impossible branch to
/// write, because the type cannot express one.
enum WorldBars: Sendable, Equatable {
    /// The same upstream as the price, at the same spelling. Every row but gold.
    case fromPriceFeed
    /// investing.com's chart API, addressed by its own numeric pair id.
    case investing(pair: String)
}

/// The venues behind the world instruments. Kept separate from `Market` because `Market` picks the data
/// source and there is one source for all of them: what differs is the trading day, and only MarketHours
/// cares.
enum WorldExchange: String, Sendable, CaseIterable {
    case newYork
    case tokyo
    /// No exchange at all: the interbank OTC market where gold actually changes hands, quoted around the
    /// clock on the same weekly rhythm as the futures venues.
    case spot
    /// ICE Futures US, which computes the dollar index and keeps that same overnight week.
    case iceUS

    /// The line shown under the ticker in the panel. The venue rather than the instrument's own name ("Dow
    /// Jones", "Gold"), for the same reason the VN rows say HOSE: when a price hasn't moved for hours, the
    /// useful thing to know is which clock it is on — and for GOLD it also answers *which* gold price,
    /// since spot and a COMEX future are some sixty dollars apart and both are called "gold".
    var label: String {
        switch self {
        case .newYork: return "New York"
        case .tokyo:   return "Tokyo"
        case .spot:    return "Spot"
        case .iceUS:   return "ICE"
        }
    }

    /// How far behind real time this venue's free data is, and therefore how old a healthy quote from it
    /// looks. Added to the staleness allowance; without it a perfectly working row greys out and stays that
    /// way, which is the single most misleading thing this app can do.
    ///
    /// Measured against the live endpoints on 2026-08-07: the equity indices answer within seconds (^DJI
    /// 0.9s, ^IXIC 4.4s) and TradingView's scanner reports `update_mode: streaming`, while Yahoo's
    /// `DX-Y.NYB` was a shade over 600 seconds behind. That is not a slow feed but the exchange's own rule —
    /// ICE mandates a ten-minute delay on data nobody pays for, and Yahoo does not report it in
    /// `exchangeDataDelayedBy`, which comes back null for every symbol here.
    ///
    /// Rounded UP to fifteen minutes rather than set to the measured ten. The feed publishes minute bars, so
    /// the true lag sweeps between 600 and 660 seconds, and the app only polls once a minute on top of that —
    /// an allowance pinned near the measurement would let a healthy row flicker grey in the seconds before
    /// each poll. The looser bound costs little, because with data this old "stale" can only usefully mean
    /// "the feed has stopped", never "this isn't the latest tick".
    var feedDelay: TimeInterval {
        switch self {
        case .newYork, .tokyo, .spot: return 0
        case .iceUS:                  return 15 * 60
        }
    }
}

/// One world instrument, as this app knows it.
struct WorldIndex: Sendable, Equatable {
    /// What the user types, and what the watchlist stores.
    let symbol: String
    /// Which upstream answers for it.
    let feed: WorldFeed
    /// The spelling that feed wants. Yahoo's indices carry a caret and its dollar index carries `-` and
    /// `.`; TradingView wants `EXCHANGE:SYMBOL`. All of it is awkward to type and easy to lose to a shell or
    /// a URL, so none of it leaves this file's neighbourhood — the sources percent-encode what they are
    /// handed, and `DX%2DY%2ENYB` and `TVC%3AGOLD` were both checked against the live endpoints first.
    let feedSymbol: String
    /// Where the sparkline's bars come from. Defaults to the price feed, which is the answer for every row
    /// whose upstream publishes a series.
    let bars: WorldBars
    /// What this row's price is denominated in. Defaulted to dollars because four of the five are, and
    /// named on the fifth because the Nikkei is not — see `Currency`.
    let currency: Currency
    let exchange: WorldExchange
    /// Other spellings accepted at the Add field, resolved to `symbol` before anything is stored. Only
    /// unambiguous ones: `DOW` is missing on purpose, because it is a real NYSE ticker (Dow Inc.) and
    /// would quietly answer a question nobody asked. `GC` and `DX` are missing for a weaker version of
    /// the same reason — two letters is short enough that a future Vietnamese listing could claim one,
    /// and the full Yahoo spelling is already accepted for anyone who thinks in it.
    let aliases: [String]

    /// `bars` last and defaulted, so the four rows that take their sparkline from their own price feed do
    /// not each have to say so.
    init(symbol: String, feed: WorldFeed, feedSymbol: String, exchange: WorldExchange,
         aliases: [String], bars: WorldBars = .fromPriceFeed, currency: Currency = .usd) {
        self.symbol = symbol
        self.feed = feed
        self.feedSymbol = feedSymbol
        self.bars = bars
        self.currency = currency
        self.exchange = exchange
        self.aliases = aliases
    }
}

extension WorldIndex {

    /// The advertised set. Every symbol and alias here was checked against the VPS board before it was
    /// added — `getliststockdata/GOLD,DXY,XAU,GC,DX` answers `[]`, so none of them can shadow a
    /// Vietnamese ticker, which is the collision that files a row under a venue that has never heard of
    /// it and leaves it on a dash for good.
    static let all: [WorldIndex] = [
        WorldIndex(symbol: "DJI", feed: .yahoo, feedSymbol: "^DJI",
                   exchange: .newYork, aliases: ["^DJI", "DJIA"]),
        WorldIndex(symbol: "IXIC", feed: .yahoo, feedSymbol: "^IXIC",
                   exchange: .newYork, aliases: ["^IXIC", "NASDAQ"]),
        // The one row in this app that is not priced in dollars or dong. At ~61,000 yen it looks like a
        // dollar figure and is not one, which is exactly why the currency is written down rather than
        // inferred: a portfolio total that folded this in as dollars would be out by a factor of 150 and
        // would still render as a believable number.
        WorldIndex(symbol: "NI225", feed: .yahoo, feedSymbol: "^N225",
                   exchange: .tokyo, aliases: ["^N225", "N225", "NIKKEI"], currency: .jpy),
        // Gold: the one row that is neither an index nor on Yahoo — see the file header. XAU is the metal's
        // own ISO code, which a trader is as likely to type as "GOLD"; GC=F stays an alias because someone
        // asking for the future by name still means this row, and there is only one gold price here.
        //
        // The only row whose bars come from somewhere other than its price feed. investing.com pair 68 is
        // spot XAU/USD, verified rather than assumed: its last minute closed 4,309.87 while the scanner read
        // 4,309.43 and Swissquote bid 4,309.02, all within one dollar of each other. Pair 8830 — the id you
        // land on searching that site for "gold" — is the COMEX future, and it printed 4,369.12 at the same
        // moment: the same sixty-dollar basis this row exists to avoid, waiting to be picked by mistake.
        WorldIndex(symbol: "GOLD", feed: .tradingView, feedSymbol: "TVC:GOLD",
                   exchange: .spot, aliases: ["XAU", "XAUUSD", "GC=F", "TVC:GOLD"],
                   bars: .investing(pair: "68")),
        // The dollar index — an index proper, computed by ICE against a basket of six currencies, and the
        // one number that answers "is the dollar strong today" without naming a pair. Left on Yahoo, which
        // quotes it ten minutes behind and with bars: the scanner would be current but would then need a
        // bars route of its own, meaning a second pair id to verify, and a delay costs nothing on an index
        // that moves hundredths of a percent in a session.
        WorldIndex(symbol: "DXY", feed: .yahoo, feedSymbol: "DX-Y.NYB",
                   exchange: .iceUS, aliases: ["DX-Y.NYB", "USDX"]),
    ]

    /// The listing for a typed or stored symbol, by canonical name or by alias. nil for everything else,
    /// including every Vietnamese ticker and crypto pair.
    static func listing(for symbol: String) -> WorldIndex? {
        let s = symbol.trimmingCharacters(in: .whitespaces).uppercased()
        return all.first { $0.symbol == s || $0.aliases.contains(s) }
    }

    /// The spelling to ask the feed for. Falls through unchanged for anything not in the table, which is
    /// what lets someone who knows Yahoo's spelling watch a symbol this app has never heard of.
    static func feedSymbol(for symbol: String) -> String {
        listing(for: symbol)?.feedSymbol ?? symbol.trimmingCharacters(in: .whitespaces).uppercased()
    }

    /// Which upstream to ask. Yahoo for anything unlisted, because that is the feed that will take an
    /// arbitrary symbol: TradingView's scanner wants an `EXCHANGE:SYMBOL` pair it already knows, so
    /// guessing it for a bare ticker would turn "not listed here" into a 404 from the wrong upstream.
    static func feed(for symbol: String) -> WorldFeed {
        listing(for: symbol)?.feed ?? .yahoo
    }

    /// Which upstream draws the sparkline. The price feed for anything unlisted, on the same reasoning as
    /// `feed(for:)`: a foreign bars source is addressed by an id that only this table knows, so there is
    /// nothing to guess with.
    static func bars(for symbol: String) -> WorldBars {
        listing(for: symbol)?.bars ?? .fromPriceFeed
    }

    /// How old a healthy quote for `symbol` looks — see `WorldExchange.feedDelay`. Zero for everything not
    /// in the table, which covers every Vietnamese ticker and crypto pair as well as an unlisted world
    /// symbol: nothing is known about the latter's feed, and assuming it is prompt errs towards a row that
    /// greys out rather than one that lies about being current.
    static func feedDelay(for symbol: String) -> TimeInterval {
        listing(for: symbol)?.exchange.feedDelay ?? 0
    }
}
