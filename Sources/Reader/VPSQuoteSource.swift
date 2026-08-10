// VPSQuoteSource.swift — Vietnamese equities and indices, from VPS's two public market-data backends.
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
//     VND, and PriceFormat renders it. Getting this wrong is a 1000× error on screen.
//   • Index values are already points (VN-Index 1704.68) and must NOT be scaled.
//   • The bars endpoint's `v` IS a share count and is never scaled. THE BOARD'S QUANTITIES ARE NOT —
//     every one of them is in tens of shares. See `sharesPerLot`, which carries the four measurements
//     that settle it; this header asserted the opposite for months and nothing on screen disagreed.

import Foundation

/// An actor, not a struct, because the daily reference prices for indices are cached across calls and
/// that cache is touched from whichever task the refresh runs on.
actor VPSQuoteSource: QuoteSource {

    /// THE BOARD REPORTS EVERY QUANTITY IN TENS OF SHARES, not shares — `lot`, `lastVolume`, `fBVol`,
    /// `fSVolume` and the sizes inside `g1`…`g7`. Nothing in the response says so, and the mistake is
    /// invisible on screen: a volume ten times too small is still a perfectly plausible volume. It shipped
    /// that way, with a comment in CLAUDE.md asserting the opposite.
    ///
    /// Established four ways, because a factor this quiet deserves more than one:
    ///
    ///   • VNDirect publishes the same session in real shares. Its `nmVolume` over this feed's `lot`, for
    ///     twenty stocks priced from 13,700 to 211,000 dong, gave 9.83–10.00 with a mean of 9.962 — the
    ///     spread being the two feeds sampled seconds apart, with VPS always the later and larger reading.
    ///   • Summed across all 404 HOSE constituents and multiplied by ten, the totals reproduce what the
    ///     Vietnamese apps print for the whole floor: session volume, traded value, and foreign buy and
    ///     sell, each landing 5–8% above a screenshot taken earlier the same morning, which is what a
    ///     session accumulator should do.
    ///   • `fBValue × 1000 ÷ (fBVol × 10)` lands on the row's own published `avePrice` to within 0.55% on
    ///     nineteen of twenty stocks. That is also what settles the foreign VALUE fields, whose unit an
    ///     earlier attempt could not pin down — it divided by a volume ten times too small, so thousands
    ///     of dong read as though it were neither dong nor thousands.
    ///   • HOSE's board lot is 100 shares, so a genuine share count is a multiple of 100. Across every one
    ///     of these fields the values were 100% multiples of ten and only 5–15% multiples of a hundred,
    ///     and the smallest `lastVolume` on the board was exactly 10 — one board lot.
    private static let sharesPerLot = 10.0

    private static let boardBase = "https://bgapidatafeed.vps.com.vn/getliststockdata/"
    private static let histBase = "https://histdatafeed.vps.com.vn/tradingview/history"

    /// How far back to ask for 1-minute bars. NOT "long enough to cover today's session" — that was a
    /// bug: an 8-hour window measured from *now* slides off the end of the session, so after ~23:00 ICT
    /// it contained no bars at all and every index silently lost its quote (which then dropped it from
    /// the menu bar entirely). It has to be long enough to still contain a whole session when the last
    /// one was days ago: a weekend plus a couple of public holidays. The bars for the most recent
    /// session are then selected from whatever comes back, so the extra span costs a bigger response,
    /// never a wrong reading.
    private static let intradayWindow: TimeInterval = 7 * 86400
    /// Daily bars are only needed for the reference close, so a month is ample even across Tết.
    private static let dailyWindow: TimeInterval = 30 * 86400

    /// Daily bars per index symbol, with the ICT day they were fetched for. Refetched when the day rolls
    /// over: daily bars only change once a session, so caching turns two requests per index per minute
    /// into one.
    private var dailyCache: [String: (day: Int, bars: Bars)] = [:]

    // MARK: - QuoteSource

    func fetchQuotes(for symbols: [String]) async throws -> [Quote] {
        let indices = symbols.filter { Ticker.isIndex($0) }
        let equities = symbols.filter { !Ticker.isIndex($0) }

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
        // Ask for a week of 1-minute bars, then keep only the most recent session's. The sparkline still
        // shows one session's shape rather than a week of noise, but it is the last session that actually
        // traded — so it doesn't go blank overnight, at a weekend, or over Tết.
        let closes = try await bars(symbol: symbol, resolution: "1", secondsBack: Self.intradayWindow)
            .lastSession().closes
        let scale = Ticker.isIndex(symbol) ? 1.0 : 1000.0
        return closes.map { $0 * scale }
    }

    // MARK: - Equities

    /// The board rows for `symbols` as quotes, WITH the ones that have not traded: a stock that has not
    /// matched today reports `lastPrice` 0, and such a row comes back with `price` 0 rather than being
    /// dropped.
    ///
    /// Separate from `fetchBoard` because the two callers want opposite things and one of them is not
    /// obvious. A watched row must never render as "0" and −100%, so the price path filters those out.
    /// Breadth must count them: an untraded stock is a fact about the session, and dropping it shrinks the
    /// denominator every ratio is measured against — which is exactly the bug this split fixes. Counting
    /// HOSE through the price path reported 365 constituents and zero untraded where the floor had 404 and
    /// 46, and the number rendered perfectly.
    func fetchBoardRows(_ symbols: [String]) async throws -> [Quote] {
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
            guard let sym = row["sym"] as? String, let last = HTTP.num(row["lastPrice"]) else { return nil }

            let ref = HTTP.num(row["r"])
            // Foreign flow, in shares, both sides carried separately — the net is derived from them, and
            // the floor's totals are summed from them for an index card.
            let foreignBought = HTTP.num(row["fBVol"]).map { $0 * Self.sharesPerLot }
            let foreignSold = HTTP.num(row["fSVolume"]).map { $0 * Self.sharesPerLot }
            // g1 is the best bid and g4 the best ask. Established from the shape, not documentation:
            // on the session probed, g1–g3 stepped DOWN from the last price (59.7, 59.6, 59.5) and g4–g6
            // stepped UP (59.8, 59.9, 60.0) — resting orders below the market are bids, above it asks,
            // and each side leads with its best. Only the top level is read; the card is a label/value
            // grid, and a three-level book wants a table it does not have.
            let bestBid = Self.bookLevel(row["g1"])
            let bestAsk = Self.bookLevel(row["g4"])
            return Quote(
                symbol: sym.uppercased(),
                market: .vietnam,
                price: last * 1000,
                reference: ref.map { $0 * 1000 },
                ceiling: HTTP.num(row["c"]).map { $0 * 1000 },
                floor: HTTP.num(row["f"]).map { $0 * 1000 },
                volume: HTTP.num(row["lot"]).map { $0 * Self.sharesPerLot },
                asOf: now,
                // Same unit as every other price on this row — thousands of dong — and the same ×1000.
                // avePrice is the session's volume-weighted average, checked against the range it must sit
                // inside (60.18 between 58.7 and 60.8 on the session it was probed on).
                high: HTTP.num(row["highPrice"]).map { $0 * 1000 },
                low: HTTP.num(row["lowPrice"]).map { $0 * 1000 },
                average: HTTP.num(row["avePrice"]).map { $0 * 1000 },
                foreignBought: foreignBought,
                foreignSold: foreignSold,
                // NOT scaled, alone among the quantities on this row: it arrives with a fractional part
                // (82270776.90) and a count of ten-share units cannot have one. It is a share count in
                // its own right, computed from a percentage of the listed shares.
                foreignRoom: HTTP.num(row["fRoom"]),
                bid: bestBid?.price, bidSize: bestBid?.size,
                ask: bestAsk?.price, askSize: bestAsk?.size
            )
        }
    }

    /// The board rows worth DRAWING: everything above, minus the stocks that have not matched today.
    ///
    /// A row whose `lastPrice` is 0 would render as a price of zero against a live reference — a −100%
    /// day on a stock nobody has traded. Dropping it leaves the panel showing the last good quote it
    /// already had, which is the truth, and a symbol with no quote at all keeps its dash.
    private func fetchBoard(_ symbols: [String]) async throws -> [Quote] {
        try await fetchBoardRows(symbols).filter { $0.price > 0 }
    }

    /// One order-book level, as the board spells it: `"59.7|2860|i"` — price in thousands of dong, size in
    /// ten-share units like every other quantity here, and a flag this app has no dictionary for. An empty
    /// side arrives as `"0|0|e"`, which the `> 0` guard turns into nil rather than into a bid at zero.
    private static func bookLevel(_ value: Any?) -> (price: Double, size: Double)? {
        guard let text = value as? String else { return nil }
        let parts = text.split(separator: "|")
        guard parts.count >= 2,
              let price = Double(parts[0]), price > 0,
              let size = Double(parts[1]), size > 0 else { return nil }
        return (price * 1000, size * sharesPerLot)
    }

    // MARK: - Indices

    private func fetchIndex(_ symbol: String) async throws -> Quote {
        // The daily series is needed for the reference close, and doubles as the price source when the
        // intraday feed returns nothing for the window — so an index keeps a quote even if the 1-minute
        // feed is briefly unavailable, instead of disappearing from the menu bar.
        let daily = try await dailySeries(symbol)
        let session = (try? await bars(symbol: symbol,
                                       resolution: "1",
                                       secondsBack: Self.intradayWindow))?.lastSession()

        guard let priceBar = session?.last ?? daily.last else { throw QuoteError.noData(symbol) }

        return Quote(
            symbol: symbol.uppercased(),
            market: .vietnam,
            price: priceBar.close,
            reference: referenceClose(from: daily, pricedAt: priceBar.time),
            ceiling: nil,           // an index has no daily band
            floor: nil,
            volume: session?.totalVolume ?? priceBar.volume,
            asOf: priceBar.time,
            // The session's range, from the DAILY bar for the day being priced rather than from the minute
            // bars. The daily bar is the venue's own high and low; the minute bars would only give the
            // extremes of the minute closes, which is a narrower and quietly wrong range.
            //
            // There is deliberately no OPEN row to go with them. The daily bar's `o` cannot be trusted for
            // an index: on the live session it read exactly the previous close, while the true opening
            // match was 1775.79, and across ten past sessions it agreed with the first minute bar
            // sometimes and with nothing at all the rest of the time. The opening auction prints inside
            // the 09:15 bar and no field this feed publishes isolates it, so the app says nothing.
            high: sessionDay(from: daily, pricedAt: priceBar.time)?.high,
            low: sessionDay(from: daily, pricedAt: priceBar.time)?.low
        )
    }

    /// The daily bars, cached for the ICT day. They only change once a session.
    private func dailySeries(_ symbol: String) async throws -> Bars {
        let today = MarketHours.tradingDay()
        if let hit = dailyCache[symbol], hit.day == today { return hit.bars }
        let fetched = try await bars(symbol: symbol, resolution: "1D", secondsBack: Self.dailyWindow)
        dailyCache[symbol] = (today, fetched)
        return fetched
    }

    /// The close the change is measured against: the last daily bar from a session BEFORE the one the
    /// price belongs to.
    ///
    /// Selecting by date rather than by "second to last" is what makes this right at every hour. Taking
    /// `count - 2` assumes the final daily bar is the priced session's own — true intraday, but wrong
    /// before the open, at a weekend, or whenever the daily feed hasn't published today's bar yet, and
    /// each of those cases silently compares against the wrong day and prints a wrong percentage.
    /// The daily bar for the session `priceTime` belongs to, which is where an index's high and low come
    /// from. nil before the venue has published today's bar, which leaves the card without a range rather
    /// than borrowing yesterday's.
    private func sessionDay(from daily: Bars, pricedAt priceTime: Date) -> Bars.Bar? {
        let cal = MarketHours.ictCalendar
        return daily.bars.last { cal.isDate($0.time, inSameDayAs: priceTime) }
    }

    private func referenceClose(from daily: Bars, pricedAt priceTime: Date) -> Double? {
        let cal = MarketHours.ictCalendar
        return daily.bars.last { !cal.isDate($0.time, inSameDayAs: priceTime) && $0.time < priceTime }?.close
    }

    // MARK: - TradingView UDF history

    /// A parsed slice of the UDF feed.
    ///
    /// Stored as one array of (time, close, volume) triples rather than three parallel arrays: the feed
    /// can carry a null in one series and not the others, and three independent compactMaps would then
    /// shift the closes against the times — attributing a price to the wrong minute, with nothing to
    /// signal it had happened.
    private struct Bars {
        struct Bar {
            let time: Date
            let close: Double
            let volume: Double
            /// The bar's own extremes, where the feed publishes them. Kept only because an INDEX has no
            /// other source for its session range: the board hands an equity `highPrice`/`lowPrice`
            /// directly, while an index gets its whole quote from these bars. Taking the range from the
            /// minute closes instead would miss every extreme reached inside a minute — measured against
            /// a real session, the minute closes topped out at 1775.20 where the day's true high was
            /// 1775.98, a number that renders perfectly and is simply not the high.
            let high: Double?
            let low: Double?
        }
        let bars: [Bar]

        var closes: [Double] { bars.map(\.close) }
        var last: Bar? { bars.last }
        var totalVolume: Double { bars.reduce(0) { $0 + $1.volume } }

        /// The bars sharing the final bar's ICT calendar day — i.e. the most recent trading session,
        /// whether that turns out to be today or last Friday.
        func lastSession() -> Bars {
            guard let end = bars.last else { return self }
            let cal = MarketHours.ictCalendar
            return Bars(bars: bars.filter { cal.isDate($0.time, inSameDayAs: end.time) })
        }
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

        // Zip the series by index so a bar is only kept when it has both a timestamp and a close.
        let rawTimes = root["t"] as? [Any] ?? []
        let rawCloses = root["c"] as? [Any] ?? []
        let rawVolumes = root["v"] as? [Any] ?? []
        let rawHighs = root["h"] as? [Any] ?? []
        let rawLows = root["l"] as? [Any] ?? []

        var parsed: [Bars.Bar] = []
        parsed.reserveCapacity(min(rawTimes.count, rawCloses.count))
        for i in 0..<min(rawTimes.count, rawCloses.count) {
            guard let t = HTTP.num(rawTimes[i]), let c = HTTP.num(rawCloses[i]) else { continue }
            let v = i < rawVolumes.count ? (HTTP.num(rawVolumes[i]) ?? 0) : 0
            parsed.append(Bars.Bar(time: Date(timeIntervalSince1970: t), close: c, volume: v,
                                   high: i < rawHighs.count ? HTTP.num(rawHighs[i]) : nil,
                                   low: i < rawLows.count ? HTTP.num(rawLows[i]) : nil))
        }
        guard !parsed.isEmpty else { throw QuoteError.noData(symbol) }

        return Bars(bars: parsed)
    }
}
