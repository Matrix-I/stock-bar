// FundamentalsSource.swift — trailing per-share figures for a Vietnamese equity, from SSI's public iBoard
// backend. Keyless, like the other two upstreams.
//
//   https://iboard-api.ssi.com.vn/statistics/company/financial-indicator?symbol=VCB
//
// It answers `{code:"SUCCESS", data:[…]}` with about twenty records, newest first, each carrying
// yearReport, lengthReport, eps, pe, pb, roe and a handful of margins as numeric STRINGS. Only some of
// those records are populated: `lengthReport` 5 is the trailing/annual row and has real figures, while the
// quarterly rows (3, 4) come back with every ratio at zero. Rather than hard-coding "take lengthReport 5",
// this takes the first record that actually has figures — same result today, and it does not break the day
// the feed starts populating a quarter.
//
// Why this endpoint and not one of the obvious alternatives, all checked live on 2026-07-30: the VPS board
// this app already calls carries 57 fields and none of them is a valuation ratio; TCBS's tcanalysis paths
// answer 404 "Service not found"; Fireant returns 401 without a token; VNDIRECT's finfo host times out
// through this machine's proxy; and SSI's own financial-ratio / company-info paths are 404 while
// financial-indicator is not.
//
// An index, an unknown ticker and a company with no filings are all the SAME answer here — HTTP 200,
// `code: "SUCCESS"`, `data: null`. That is treated as "nothing to report", not as a failure, because it is
// the normal case for half of a typical watchlist.

import Foundation

actor FundamentalsSource {

    private static let base = "https://iboard-api.ssi.com.vn/statistics/company/financial-indicator"

    /// One entry per symbol, with the ICT day it was fetched for. Cached because these figures change once
    /// a quarter and the panel would otherwise re-ask for all of them every time it opens.
    ///
    /// Negative results are cached too. Half a watchlist is indices and crypto, and re-requesting a
    /// guaranteed `data: null` on every open is the same waste as re-requesting a real one.
    private var cache: [String: (day: Int, value: Fundamentals)] = [:]

    /// Trailing figures for `symbol`, or `.none` when the feed has nothing for it.
    ///
    /// Throws only on a transport failure, so the caller can tell "this company has no filings" from "the
    /// network is down" — the first is permanent and worth caching, the second is not.
    func fetch(for symbol: String) async throws -> Fundamentals {
        let wanted = symbol.uppercased()
        // An index has no earnings and no book, and the feed says so with a round trip. Answer without one.
        guard !Ticker.isIndex(wanted) else { return .none }

        let today = MarketHours.tradingDay()
        if let hit = cache[wanted], hit.day == today { return hit.value }

        var components = URLComponents(string: Self.base)!
        components.queryItems = [.init(name: "symbol", value: wanted)]
        guard let url = components.url else { throw QuoteError.malformed("fundamentals URL") }

        guard let root = try await HTTP.json(url) as? [String: Any] else {
            throw QuoteError.malformed("fundamentals: expected a JSON object")
        }
        // `data` is null for anything unlisted — a successful answer meaning "no figures", so it is cached
        // like any other and not raised as an error.
        let rows = root["data"] as? [[String: Any]] ?? []
        let value = Self.newest(from: rows)
        cache[wanted] = (today, value)
        return value
    }

    /// The first record carrying real figures. The feed orders newest-first, so "first usable" is "most
    /// recent usable".
    private static func newest(from rows: [[String: Any]]) -> Fundamentals {
        for row in rows {
            let eps = HTTP.num(row["eps"])
            let pe = HTTP.num(row["pe"])
            let pb = HTTP.num(row["pb"])
            // A zeroed row is this feed's "not reported", and zero EPS would also divide badly downstream.
            guard let eps, eps != 0 else { continue }
            let bvps = Fundamentals.bookValuePerShare(pe: pe, eps: eps, pb: pb)
            return Fundamentals(earningsPerShare: eps,
                                bookValuePerShare: bvps,
                                year: HTTP.num(row["yearReport"]).map { Int($0) })
        }
        return .none
    }
}
