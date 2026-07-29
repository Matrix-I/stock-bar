// Quote.swift — the one shape every data source normalises into, so the menu bar and the popover
// never care whether a row came from a Vietnamese exchange or a crypto venue.
//
// Prices are stored in the instrument's own display unit: VND for HOSE/HNX tickers (already unscaled
// — see VNQuoteSource, whose upstream reports some fields in units of 1 VND and others in 1000s), and
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

    /// Session volume in shares (VN) or base units (crypto).
    let volume: Double?

    /// When this quote was observed — used to grey out a stale row when a fetch has been failing.
    let asOf: Date

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
}
