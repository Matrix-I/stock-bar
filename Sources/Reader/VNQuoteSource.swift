// VNQuoteSource.swift — Vietnamese equities and indices, from VPS's two public market-data backends.
// These are the JSON services behind VPS's own web board; they are community-known rather than
// formally documented, need no key, and were probed live before this was written.
//
// TWO endpoints, because neither alone covers both instrument kinds:
//
//   1. Equities — https://bgapidatafeed.vps.com.vn/getliststockdata/VCB,FPT,HPG
//      One request returns EVERY requested ticker, which is why this is the primary: N tickers cost
//      one request, so the whole watchlist refreshes within a single call. Fields used:
//        sym       ticker                  lastPrice  last matched price
//        r         reference (tham chiếu)  c          ceiling (trần)      f  floor (sàn)
//        lot       session volume
//      Indices are NOT served here — getliststockdata/VNINDEX returns [].
//
//   2. Indices — https://histdatafeed.vps.com.vn/tradingview/history?symbol=VNINDEX&resolution=1
//      A TradingView UDF feed: {s:"ok", t:[epoch], o:[], h:[], l:[], c:[], v:[]}. resolution=1 is
//      1-minute bars, so the last element is the live value AND the whole `c` array is the intraday
//      sparkline — one request serves both, which is why indices don't need a second call per tick.
//      The previous session's close (the reference the change is measured against) comes from the
//      same endpoint at resolution=1D and is cached for the day, since it only changes overnight.
//
// PRICE SCALING — verified against both endpoints on 2026-07-29:
//   • Equity prices come in THOUSANDS of VND: VCB reads 54.6, meaning 54,600 VND. Ceiling, floor and
//     reference use the same unit. We multiply by 1000 on the way in so `Quote.price` is always real
//     VND, and Formatting divides again for display. Getting this wrong is a 1000× error on screen.
//   • Index values are already points (VN-Index 1704.68) and must NOT be scaled.
// `lot`/`v` are share counts and are never scaled.

import Foundation

/// An actor, not a struct, because the daily reference prices for indices are cached across calls and
/// that cache is touched from whichever task the refresh runs on.
actor VNQuoteSource: QuoteSource {

    private static let boardBase = "https://bgapidatafeed.vps.com.vn/getliststockdata/"
    private static let histBase = "https://histdatafeed.vps.com.vn/tradingview/history"

    /// Previous-session close per index symbol, with the local day it was fetched for. Refetched when
    /// the day rolls over; an index's reference cannot change intraday, so caching it turns 2
    /// requests-per-index-per-minute into 1.
    private var indexReference: [String: (day: Int, close: Double)] = [:]

    // MARK: - QuoteSource

    func fetchQuotes(for symbols: [String]) async throws -> [Quote] {
        let indices = symbols.filter { isIndexSymbol($0) }
        let equities = symbols.filter { !isIndexSymbol($0) }

        // Run the (single) board request and the per-index requests concurrently — the indices are
        // independent of each other and of the board, so there's no reason to serialise them.
        async let equityQuotes = equities.isEmpty ? [] : fetchBoard(equities)
        let indexQuotes = try await withThrowingTaskGroup(of: Quote?.self) { group in
            for symbol in indices {
                group.addTask { try? await self.fetchIndex(symbol) }
            }
            var out: [Quote] = []
            for try await q in group { if let q { out.append(q) } }
            return out
        }
        return try await equityQuotes + indexQuotes
    }

    func fetchHistory(for symbol: String) async throws -> [Double] {
        // 1-minute bars over the last 8 hours: long enough to cover a full session (09:00–15:00 ICT)
        // from any point in the day, short enough that a closed-market fetch still returns today's
        // shape rather than a week of noise.
        let closes = try await bars(symbol: symbol, resolution: "1", secondsBack: 8 * 3600).closes
        let scale = isIndexSymbol(symbol) ? 1.0 : 1000.0
        return closes.map { $0 * scale }
    }

    // MARK: - Equities

    private func fetchBoard(_ symbols: [String]) async throws -> [Quote] {
        // The path segment is a comma-separated ticker list. Tickers are A-Z/0-9 only, so no escaping
        // is needed beyond the join; we uppercase because the endpoint is case-sensitive and returns
        // [] for lowercase input.
        let list = symbols.map { $0.uppercased() }.joined(separator: ",")
        guard let url = URL(string: Self.boardBase + list) else { throw QuoteError.malformed("board URL") }

        guard let rows = try await HTTP.json(url) as? [[String: Any]] else {
            throw QuoteError.malformed("board: expected a JSON array")
        }

        let now = Date()
        return rows.compactMap { row -> Quote? in
            guard let sym = row["sym"] as? String,
                  let last = HTTP.num(row["lastPrice"]), last > 0
            else { return nil }

            // A stock that hasn't traded yet today reports lastPrice 0; the reference is then the only
            // meaningful number, so fall back to it rather than dropping the row (a watched ticker
            // vanishing from the list looks like a bug).
            let ref = HTTP.num(row["r"])
            return Quote(
                symbol: sym.uppercased(),
                market: .vietnam,
                price: last * 1000,
                reference: ref.map { $0 * 1000 },
                ceiling: HTTP.num(row["c"]).map { $0 * 1000 },
                floor: HTTP.num(row["f"]).map { $0 * 1000 },
                volume: HTTP.num(row["lot"]),
                asOf: now
            )
        }
    }

    // MARK: - Indices

    private func fetchIndex(_ symbol: String) async throws -> Quote {
        let intraday = try await bars(symbol: symbol, resolution: "1", secondsBack: 8 * 3600)
        guard let last = intraday.closes.last else { throw QuoteError.noData(symbol) }

        return Quote(
            symbol: symbol.uppercased(),
            market: .vietnam,
            price: last,
            reference: try? await previousClose(symbol),
            ceiling: nil,           // an index has no daily band
            floor: nil,
            volume: intraday.volumes.reduce(0, +),
            asOf: intraday.lastBarDate ?? Date()
        )
    }

    /// The previous session's close, cached for the calendar day. On a cache miss it reads the last two
    /// daily bars and takes the *second to last* — the final one is today's still-forming bar.
    private func previousClose(_ symbol: String) async throws -> Double {
        let today = Calendar.current.ordinality(of: .day, in: .era, for: Date()) ?? 0
        if let hit = indexReference[symbol], hit.day == today { return hit.close }

        // 14 days back, not 2: weekends and a public holiday run can easily leave fewer than two
        // trading days in a short window, and an empty result here would leave the row with no
        // percentage at all.
        let daily = try await bars(symbol: symbol, resolution: "1D", secondsBack: 14 * 86400)
        guard daily.closes.count >= 2 else { throw QuoteError.noData("\(symbol) daily") }
        let prev = daily.closes[daily.closes.count - 2]
        indexReference[symbol] = (today, prev)
        return prev
    }

    // MARK: - TradingView UDF history

    private struct Bars {
        let closes: [Double]
        let volumes: [Double]
        let lastBarDate: Date?
    }

    private func bars(symbol: String, resolution: String, secondsBack: TimeInterval) async throws -> Bars {
        let to = Int(Date().timeIntervalSince1970)
        let from = to - Int(secondsBack)
        var c = URLComponents(string: Self.histBase)!
        c.queryItems = [
            .init(name: "symbol", value: symbol.uppercased()),
            .init(name: "resolution", value: resolution),
            .init(name: "from", value: String(from)),
            .init(name: "to", value: String(to)),
        ]
        guard let url = c.url else { throw QuoteError.malformed("history URL") }

        guard let root = try await HTTP.json(url) as? [String: Any] else {
            throw QuoteError.malformed("history: expected a JSON object")
        }
        // The feed answers `s:"no_data"` (with empty arrays) for an unknown symbol rather than a 404 —
        // e.g. UPINDEX, which it doesn't carry. Treat that as "no data", not as a transport error, so
        // the UI can say "unknown symbol" instead of "network failed".
        guard let status = root["s"] as? String else { throw QuoteError.malformed("history: no status") }
        guard status == "ok" else { throw QuoteError.noData(symbol) }

        let closes = (root["c"] as? [Any])?.compactMap { HTTP.num($0) } ?? []
        let volumes = (root["v"] as? [Any])?.compactMap { HTTP.num($0) } ?? []
        let times = (root["t"] as? [Any])?.compactMap { HTTP.num($0) } ?? []
        guard !closes.isEmpty else { throw QuoteError.noData(symbol) }

        return Bars(closes: closes,
                    volumes: volumes,
                    lastBarDate: times.last.map { Date(timeIntervalSince1970: $0) })
    }
}
