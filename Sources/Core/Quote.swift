// Quote.swift — the one shape every data source normalises into, so the menu bar and the popover
// never care whether a row came from a Vietnamese exchange or a crypto venue.
//
// Prices are stored in the instrument's own display unit: VND for HOSE/HNX tickers (already unscaled
// — see VPSQuoteSource, whose upstream reports some fields in units of 1 VND and others in 1000s), and
// USD for crypto pairs. Formatting is the view's job (see PriceFormat), not the model's.

import Foundation

/// Where a quote sits relative to the day's permitted band. Vietnamese boards colour these
/// distinctly, which is the main reason this is modelled rather than inferred from the sign alone.
enum PriceBand: Sendable, Equatable {
    case ceiling      // trần  — locked at the daily upper limit
    case floor        // sàn   — locked at the daily lower limit
    case up
    case down
    case unchanged    // tham chiếu
}

extension PriceBand {
    /// The arrow prefixed to a change. Ceiling/floor get a doubled glyph so the two "locked" states stay
    /// distinguishable for anyone who can't rely on the colour.
    var arrow: String {
        switch self {
        case .ceiling:   return "⇑"
        case .floor:     return "⇓"
        case .up:        return "▲"
        case .down:      return "▼"
        case .unchanged: return "="
        }
    }
}

/// One instrument's current state. Everything past `price` is optional because the sources differ in
/// what they expose: a crypto ticker has no ceiling/floor band, and an index has no meaningful
/// bid/ask. A field that is nil is simply not rendered rather than shown as zero.
struct Quote: Sendable, Identifiable {
    var id: String { symbol }

    let symbol: String
    let market: Market

    /// Last traded (or last matched) price, in the instrument's display unit.
    let price: Double
    /// Yesterday's close for crypto, or the session's reference price (giá tham chiếu) for VN — the
    /// baseline `change` is measured against.
    let reference: Double?

    let ceiling: Double?
    let floor: Double?

    /// Session volume in shares (VN), base units (crypto) or contracts (the gold future). Absent for an
    /// index that doesn't publish one.
    let volume: Double?

    /// When this quote was observed — used to grey out a stale row when a fetch has been failing.
    let asOf: Date

    /// The session's traded range so far — the day for an exchange, the rolling 24 hours for crypto,
    /// whichever the feed's own convention is. Every feed this app reads publishes the pair in the same
    /// response the price came from, so carrying it costs no extra request; it is simply data that used
    /// to be thrown away.
    let high: Double?
    let low: Double?

    /// Volume-weighted average traded price for the session, where the venue computes one (the VN board's
    /// `avePrice`). The number that says whether the current print is above or below where the day's
    /// actual business was done.
    let average: Double?

    /// Net foreign buying this session, in SHARES, signed: positive bought, negative sold. VN equities
    /// only — khối ngoại is a fixture of every Vietnamese board, and no other market here reports it.
    ///
    /// Shares and not value, deliberately. The board also carries fBValue/fSValue, but their unit does not
    /// reconcile: for a session where 132k shares traded around 60,000 VND the buy value read 7.98e7,
    /// which is neither dong (100× too small) nor thousands (10× too large). A number whose unit cannot be
    /// verified is not shown — the same rule the gold gap was built under.
    let foreignNet: Double?

    /// Memberwise, with the enrichment fields defaulted. Written out because the synthesised initialiser
    /// would demand all four at every call site, and most sources have only some of them to give.
    init(symbol: String, market: Market, price: Double, reference: Double?,
         ceiling: Double?, floor: Double?, volume: Double?, asOf: Date,
         high: Double? = nil, low: Double? = nil,
         average: Double? = nil, foreignNet: Double? = nil) {
        self.symbol = symbol
        self.market = market
        self.price = price
        self.reference = reference
        self.ceiling = ceiling
        self.floor = floor
        self.volume = volume
        self.asOf = asOf
        self.high = high
        self.low = low
        self.average = average
        self.foreignNet = foreignNet
    }

    /// Absolute move against `reference`. nil when no reference is available, in which case the view
    /// shows the bare price with no arrow.
    var change: Double? {
        guard let reference, reference > 0 else { return nil }
        return price - reference
    }

    var changePercent: Double? {
        guard let reference, reference > 0 else { return nil }
        return (price - reference) / reference * 100
    }

    /// Band classification. Ceiling/floor win over the plain up/down comparison because a VN board
    /// colours a ceiling-locked stock purple even though it is, arithmetically, also "up".
    ///
    /// The ceiling/floor comparison uses a small relative epsilon rather than `==`: the band limits
    /// arrive as rounded tick values and a float equality test on two independently rounded decimals
    /// misses often enough to be a visible bug (a stock sitting exactly on its ceiling rendering
    /// green instead of purple).
    var band: PriceBand {
        if let ceiling, abs(price - ceiling) <= max(ceiling, 1) * 1e-6 { return .ceiling }
        if let floor, abs(price - floor) <= max(floor, 1) * 1e-6 { return .floor }
        guard let change else { return .unchanged }
        if change > 0 { return .up }
        if change < 0 { return .down }
        return .unchanged
    }

    /// Whether this is an index rather than a tradable stock — see `Ticker.isIndex`. Read by the row,
    /// the tooltip and the menu-bar label, all of which format an index differently.
    var isIndex: Bool { Ticker.isIndex(symbol) }

    // MARK: - The day boundary

    /// Whether this reading is about the ICT day `now` falls in.
    ///
    /// A finished session's numbers do not expire when it closes — the VPS board keeps serving the closing
    /// price against the closing session's reference until it rolls over on the morning of the next one, and
    /// an index's last 1-minute bar is likewise the last one that exists. So "the feed answered" is not the
    /// same as "this is about today", and the test is the reading's own timestamp: taken on this ICT day,
    /// at or after the open.
    ///
    /// Checking `asOf` rather than the clock is what covers the awkward window. At 09:05 the board is in the
    /// opening auction and has no matched price yet, so no new quote arrives; a clock-only test would decide
    /// the session had started and let the previous day's change reappear for the ten minutes until one does.
    ///
    /// Crypto is always current. Binance quotes against a rolling 24-hour window rather than a session, so
    /// its baseline has no day boundary to fall behind.
    func isFromCurrentSession(at now: Date) -> Bool {
        guard market == .vietnam else { return true }
        // The domestic gold and FX rows are on `.vietnam` but not on HOSE's clock, and the rebase below is
        // wrong for them twice over. They have no previous close to fall behind — PNJ publishes none — so
        // rebasing would set a reference where the feed deliberately left none and turn a bare price into a
        // flat one, inventing the very "unchanged" reading their missing reference exists to avoid. And
        // their day does not begin at 09:00: a board published on a Saturday morning is current news on
        // Saturday afternoon, which `hasSessionStarted` would deny for the whole weekend.
        guard !DomesticIndex.isDomestic(symbol) else { return true }
        return MarketHours.isSameSessionDay(asOf, now)
            && MarketHours.hasSessionStarted(market, at: asOf)
    }

    /// This quote as it should read at `now`: unchanged while its own session is the current one, and
    /// rebased onto its last close once the day has rolled past it.
    ///
    /// Without this, a VN row goes on reporting the last session's move — green, +3.48% — from midnight
    /// until the next board rollover, and all weekend. That figure is not wrong so much as answering
    /// yesterday's question: nothing has traded yet, so there is nothing up or down about today.
    ///
    /// The rebase is not a fiction. HOSE's reference for a session IS the previous session's close, so
    /// setting `reference` to the last price we have is exactly the number the board will publish itself a
    /// few hours later — we just aren't waiting for it. `price` is left alone, because the last close is
    /// still the most recent price that exists, and `asOf` too, so the panel keeps saying which session the
    /// reading came from.
    ///
    /// Ceiling and floor go, though, and that is the one place information is deliberately dropped. They
    /// are ±7% of the OLD reference, so keeping them beside the new one shows a band that doesn't belong to
    /// it — and `band` reads them first, which would paint a stock that closed limit-up purple all night
    /// with a change of zero beside it. Volume stays: it is the last session's real turnover, and `asOf`
    /// says which session that was.
    func rebasedForPendingSession(at now: Date) -> Quote {
        guard !isFromCurrentSession(at: now) else { return self }
        // The range, average and foreign flow stay for the same reason volume does: they are facts about
        // the finished session, `asOf` says which session that was, and unlike the band they are not read
        // back into `band` — keeping them cannot recolour the row.
        return Quote(symbol: symbol, market: market, price: price, reference: price,
                     ceiling: nil, floor: nil, volume: volume, asOf: asOf,
                     high: high, low: low, average: average, foreignNet: foreignNet)
    }
}
