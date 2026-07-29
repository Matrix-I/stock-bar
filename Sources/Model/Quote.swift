// Quote.swift — the one shape every data source normalises into, so the menu bar and the popover
// never care whether a row came from a Vietnamese exchange or a crypto venue.
//
// Prices are stored in the instrument's own display unit: VND for HOSE/HNX tickers (already unscaled
// — see VNQuoteSource, whose upstream reports some fields in units of 1 VND and others in 1000s), and
// USD for crypto pairs. Formatting is the view's job (see Formatting.swift), not the model's.

import Foundation

/// Which market an instrument trades on. Drives the refresh cadence (a closed exchange is not polled;
/// crypto is 24/7), the price formatting, and the up/down colour convention.
enum Market: String, Codable, Sendable, CaseIterable {
    /// Vietnamese equities and indices (HOSE / HNX / UPCOM). Session hours in MarketHours.
    case vietnam
    /// Crypto pairs — always open.
    case crypto
}

/// Where a quote sits relative to the day's permitted band. Vietnamese boards colour these
/// distinctly, which is the main reason this is modelled rather than inferred from the sign alone.
enum PriceBand: Sendable {
    case ceiling      // trần  — locked at the daily upper limit
    case floor        // sàn   — locked at the daily lower limit
    case up
    case down
    case unchanged    // tham chiếu
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
}

/// A user-configured row in the menu bar / popover. Kept separate from `Quote` because it persists
/// (UserDefaults, see Watchlist) while a Quote is transient: the watchlist survives a launch where
/// every fetch failed.
struct WatchedSymbol: Codable, Sendable, Hashable, Identifiable {
    var id: String { "\(market.rawValue):\(symbol)" }

    /// Exchange ticker (VN: "VCB", "VNINDEX") or venue pair (crypto: "BTCUSDT").
    let symbol: String
    let market: Market
    /// Whether this row is one of the ones rendered in the menu bar itself. The popover always shows
    /// every watched symbol; the menu bar shows only the pinned ones, because horizontal space there
    /// is the scarcest resource in the whole app.
    var pinnedToMenuBar: Bool

    /// Short label for the menu bar. VNINDEX is the one symbol whose ticker is too long to sit in a
    /// menu bar next to anything else, so it gets an alias; everything else uses its own ticker.
    var menuBarLabel: String {
        switch symbol.uppercased() {
        case "VNINDEX":  return "VNI"
        case "VN30":     return "VN30"
        case "HNXINDEX": return "HNX"
        case "BTCUSDT":  return "BTC"
        case "ETHUSDT":  return "ETH"
        default:
            // Crypto pairs are stored with their quote currency ("SOLUSDT"); the menu bar only has
            // room for the base asset, and USDT is the only quote currency this app requests.
            if market == .crypto, symbol.uppercased().hasSuffix("USDT") {
                return String(symbol.dropLast(4)).uppercased()
            }
            return symbol.uppercased()
        }
    }
}
