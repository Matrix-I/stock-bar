// WorldIndex.swift — the world indices this app carries, in one table.
//
// A table rather than three special cases spread through the tree, because a single index is spelled four
// different ways by the time it reaches the screen: the user types `DJI`, the feed wants `^DJI`, the hours
// that decide when it is worth polling belong to New York, and the panel wants a venue line under the
// ticker. Adding an index is one row here plus, if it trades somewhere new, one window in MarketHours.
//
// The set is deliberately small and explicit. WorldQuoteSource will forward any symbol Yahoo recognises,
// so nothing here rejects an unlisted one — but a symbol outside this table has no venue, which means the
// session gate can only guess at its hours, so it is not something to advertise.

import Foundation

/// The venues behind the world indices. Kept separate from `Market` because `Market` picks the data source
/// and there is one source for all of them: what differs is the trading day, and only MarketHours cares.
enum WorldExchange: String, Sendable, CaseIterable {
    case newYork
    case tokyo

    /// The line shown under the ticker in the panel. The venue rather than the index's own name ("Dow
    /// Jones"), for the same reason the VN rows say HOSE: when a price hasn't moved for hours, the useful
    /// thing to know is which clock it is on.
    var label: String {
        switch self {
        case .newYork: return "New York"
        case .tokyo:   return "Tokyo"
        }
    }
}

/// One world index, as this app knows it.
struct WorldIndex: Sendable, Equatable {
    /// What the user types, and what the watchlist stores.
    let symbol: String
    /// Yahoo's own spelling. Indices carry a caret there, which is awkward to type and easy to lose to a
    /// shell or a URL, so it never leaves this file's neighbourhood.
    let yahoo: String
    let exchange: WorldExchange
    /// Other spellings accepted at the Add field, resolved to `symbol` before anything is stored. Only
    /// unambiguous ones: `DOW` is missing on purpose, because it is a real NYSE ticker (Dow Inc.) and
    /// would quietly answer a question nobody asked.
    let aliases: [String]
}

extension WorldIndex {

    static let all: [WorldIndex] = [
        WorldIndex(symbol: "DJI", yahoo: "^DJI", exchange: .newYork, aliases: ["^DJI", "DJIA"]),
        WorldIndex(symbol: "IXIC", yahoo: "^IXIC", exchange: .newYork, aliases: ["^IXIC", "NASDAQ"]),
        WorldIndex(symbol: "NI225", yahoo: "^N225", exchange: .tokyo, aliases: ["^N225", "N225", "NIKKEI"]),
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
}
