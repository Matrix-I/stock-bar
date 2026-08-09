// BreadthSource.swift — how many stocks on a floor are up and how many are down.
//
// NO UPSTREAM PUBLISHES THIS. Every candidate was probed on 2026-08-09 and none answers: VPS's board host
// has no index or market endpoint at all (`getlistindexdata`, `getindexdata`, `getmarketinfo` and friends
// all 404 from Express itself), SSI's iBoard API answers a structured "Request not found" for every
// statistics path tried, and VNDirect's finfo has no breadth resource. So the number is counted here.
//
// TWO SOURCES, AND THE SPLIT IS THE WHOLE DESIGN:
//
//   • WHICH STOCKS — VNDirect's finfo, once per ICT day.
//     https://api-finfo.vndirect.com.vn/v4/stocks?q=type:STOCK~floor:HOSE~status:listed&size=800
//     Membership changes on the order of weeks, so a daily fetch is generous. `type:STOCK` matters: the
//     same host's price endpoint returns 428 rows for HOSE against this one's 404, the difference being
//     ETFs, funds and warrants, which no board counts in its breadth.
//
//   • WHAT THEY COST — the VPS board, the app's own price source, in one request for all of them.
//     Using VNDirect for prices too would have been one request fewer and was rejected: this app's
//     VNINDEX breadth would then be able to disagree with its own VCB row, which is the class of bug
//     `PriceFormat` and the single-price-source rule exist to prevent. The list is a slowly-changing
//     fact; the prices are the thing that must match what is drawn.
//
// The two were checked against each other before this was written, and agreed exactly: 176 up and 143
// down for HOSE on the same session, counted independently from each feed. Where they differ is the part
// VPS is better at — it reports `lastPrice` 0 for a stock that never matched, so 46 untraded tickers can
// be told from 63 genuinely flat ones, while VNDirect's close is always populated and folds all 109
// together.
//
// COST, since this is the heaviest request in the app: 404 tickers is a 1,831-character path and about
// 409 KB back, in 0.7s. It is fetched only while the panel is open and cached for a minute, so it costs
// one request per panel visit rather than one per poll.

import Foundation

actor BreadthSource {

    private static let listBase = "https://api-finfo.vndirect.com.vn/v4/stocks"
    /// Above any Vietnamese floor's listing count with room to spare — HOSE was 404 and HNX 299 when this
    /// was written. Asking for more than exists is free; asking for too few would silently truncate the
    /// denominator and skew every count computed from it.
    private static let listSize = 800

    /// How long a count stands before it is recomputed. A minute, matching the app's own poll: the panel
    /// can be opened and closed repeatedly without paying 400 KB each time, and nothing on screen is ever
    /// more than one refresh cycle behind the rows above it.
    private static let cacheLifetime: TimeInterval = 60

    private let board = VPSQuoteSource()
    /// Constituents per floor, with the ICT day they were fetched on — see the header for why daily.
    private var listCache: [String: (day: Int, codes: [String])] = [:]
    private var breadthCache: [String: (at: Date, value: Breadth)] = [:]

    func breadth(for floor: String, now: Date = Date()) async throws -> Breadth {
        if let cached = breadthCache[floor], now.timeIntervalSince(cached.at) < Self.cacheLifetime {
            return cached.value
        }
        let codes = try await constituents(of: floor, now: now)
        guard !codes.isEmpty else { throw QuoteError.noData("\(floor) constituents") }

        // One request for the whole floor: the board takes a comma-separated list and answers it all at
        // once, however long the list gets.
        //
        // `fetchBoardRows` and NOT `fetchQuotes`, which is the difference between a right count and a
        // plausible wrong one. The price path drops a stock that has not matched today, because a watched
        // row rendering "0" and −100% is worse than one keeping its last good value; counting through it
        // reported HOSE as 365 constituents with zero untraded, where the floor had 404 and 46 had simply
        // not traded yet. Both numbers render perfectly and only one is true.
        let quotes = try await board.fetchBoardRows(codes)
        let value = Breadth.count(floor: floor, quotes: quotes)
        breadthCache[floor] = (now, value)
        return value
    }

    /// The floor's listed ordinary shares, cached for the ICT day.
    ///
    /// The day is the app's own trading day rather than the machine's, matching every other daily boundary
    /// here: a laptop in another zone would otherwise roll the cache over in the middle of a session.
    private func constituents(of floor: String, now: Date) async throws -> [String] {
        let day = MarketHours.tradingDay(at: now)
        if let cached = listCache[floor], cached.day == day { return cached.codes }

        var components = URLComponents(string: Self.listBase)!
        components.queryItems = [
            URLQueryItem(name: "q", value: "type:STOCK~floor:\(floor)~status:listed"),
            URLQueryItem(name: "size", value: String(Self.listSize)),
        ]
        guard let url = components.url else { throw QuoteError.malformed("constituents URL") }
        guard let root = try await HTTP.json(url) as? [String: Any],
              let rows = root["data"] as? [[String: Any]] else {
            throw QuoteError.malformed("constituents: expected a data array")
        }
        let codes = rows.compactMap { $0["code"] as? String }.filter { !$0.isEmpty }
        // Only cache a list that actually arrived. Caching an empty one would pin the floor to "no
        // breadth" for the rest of the day over a single failed request.
        if !codes.isEmpty { listCache[floor] = (day, codes) }
        return codes
    }
}
