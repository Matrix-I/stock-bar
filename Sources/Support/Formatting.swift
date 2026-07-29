// Formatting.swift — how a quote is turned into the strings and colours on screen. Kept in one place
// because the menu-bar glyph (AppKit, NSColor) and the popover (SwiftUI, Color) must agree: a row that
// reads purple in the popover and green in the menu bar is worse than either alone.

import SwiftUI
import AppKit

// MARK: - Colours

/// The Vietnamese board convention, which is NOT the Western one and is the single most likely thing
/// to look "wrong" to someone used to US tickers:
///
///   • green   — tăng (up)
///   • red     — giảm (down)
///   • purple  — trần (ceiling: locked at the daily upper limit, +7% on HOSE)
///   • cyan    — sàn  (floor: locked at the daily lower limit)
///   • yellow  — tham chiếu (unchanged from the reference price)
///
/// Crypto uses the same green/red for up/down and has no band colours, so the same function serves
/// both markets: a crypto quote simply never reports .ceiling/.floor/.unchanged-with-yellow.
///
/// These are the system semantic colours rather than hand-picked hex values so they stay legible in
/// both light and dark menu bars, and shift correctly under Increase Contrast.
func bandColor(_ band: PriceBand, market: Market) -> Color {
    switch band {
    case .ceiling:   return market == .vietnam ? Color(nsColor: .systemPurple) : Color(nsColor: .systemGreen)
    case .floor:     return market == .vietnam ? Color(nsColor: .systemTeal)   : Color(nsColor: .systemRed)
    case .up:        return Color(nsColor: .systemGreen)
    case .down:      return Color(nsColor: .systemRed)
    // A VN board paints the reference price yellow. For crypto, "exactly unchanged" is a rounding
    // artefact rather than a real state, so it reads as ordinary secondary text instead of an alarm
    // colour.
    case .unchanged: return market == .vietnam ? Color(nsColor: .systemYellow) : Color(nsColor: .secondaryLabelColor)
    }
}

/// The NSColor half of `bandColor`, for the baked menu-bar image. Same mapping — kept as a separate
/// function rather than converting the SwiftUI Color at draw time because NSColor(Color) round-trips
/// through the current appearance and loses the dynamic (light/dark-adaptive) behaviour of the
/// semantic colours, which is exactly what the menu bar needs to keep.
func bandNSColor(_ band: PriceBand, market: Market) -> NSColor {
    switch band {
    case .ceiling:   return market == .vietnam ? .systemPurple : .systemGreen
    case .floor:     return market == .vietnam ? .systemTeal   : .systemRed
    case .up:        return .systemGreen
    case .down:      return .systemRed
    case .unchanged: return market == .vietnam ? .systemYellow : .secondaryLabelColor
    }
}

/// The arrow prefixed to a change. Ceiling/floor get a doubled glyph so the two "locked" states stay
/// distinguishable for anyone who can't rely on the colour.
func bandArrow(_ band: PriceBand) -> String {
    switch band {
    case .ceiling:   return "⇑"
    case .floor:     return "⇓"
    case .up:        return "▲"
    case .down:      return "▼"
    case .unchanged: return "="
    }
}

// MARK: - Prices

/// A VND price for the popover: grouped thousands, no decimals above 1000 ("62,400"), one decimal
/// below it so a sub-1000-VND penny stock doesn't collapse to a flat integer. Indices (VN-Index at
/// ~1,250.36) keep two decimals — that's how every Vietnamese board prints them.
func fmtVNPrice(_ value: Double, isIndex: Bool) -> String {
    let f = NumberFormatter()
    f.numberStyle = .decimal
    f.groupingSeparator = ","
    f.decimalSeparator = "."
    if isIndex {
        f.minimumFractionDigits = 2
        f.maximumFractionDigits = 2
    } else {
        f.maximumFractionDigits = value < 1000 ? 1 : 0
    }
    return f.string(from: NSNumber(value: value)) ?? String(value)
}

/// A crypto price. Precision scales with magnitude because the same formatter has to serve BTC at
/// ~64,000 and a token at 0.00004: two decimals read as "0.00" there, which is useless.
///
/// Above 1 the decimals are FIXED at two rather than merely capped. Two reasons: the price is never
/// rounded away (a BTC tick of 64,134.01 shows its cents), and the rendered width doesn't change when a
/// price happens to land on a whole number — with a variable count the menu-bar item jitters sideways
/// every time the cents hit .00.
func fmtCryptoPrice(_ value: Double) -> String {
    let f = NumberFormatter()
    f.numberStyle = .decimal
    f.groupingSeparator = ","
    f.decimalSeparator = "."
    switch abs(value) {
    case 1...:       f.minimumFractionDigits = 2; f.maximumFractionDigits = 2
    case 0.01..<1:   f.maximumFractionDigits = 4
    default:         f.maximumFractionDigits = 8
    }
    return f.string(from: NSNumber(value: value)) ?? String(value)
}

/// THE price formatter — the single one both the menu bar and the popover call.
///
/// It exists because they used to format independently: the menu bar abbreviated and rounded
/// (VN-Index 1704.68 → "1705", BTC 64,134 → "64.0k") while the popover printed the exact figure, so the
/// same instrument read as two different prices depending on where you looked. Any future change to how
/// a price appears belongs here, not at a call site.
func fmtPrice(_ value: Double, market: Market, isIndex: Bool) -> String {
    market == .vietnam ? fmtVNPrice(value, isIndex: isIndex) : fmtCryptoPrice(value)
}

/// The signed percentage shown next to the price, e.g. "+0.82%" / "−1.14%". Uses U+2212 MINUS SIGN
/// rather than a hyphen so the negative sign has the same width as the plus in a monospaced-digit
/// font — with a hyphen the label visibly shifts every time a quote crosses zero.
func fmtChangePercent(_ pct: Double) -> String {
    let sign = pct > 0 ? "+" : (pct < 0 ? "\u{2212}" : "")
    return sign + String(format: "%.2f%%", abs(pct))
}

/// The signed absolute change, formatted through `fmtPrice` so it carries the same precision as the
/// price it is a delta of.
func fmtChange(_ value: Double, market: Market, isIndex: Bool) -> String {
    let sign = value > 0 ? "+" : (value < 0 ? "\u{2212}" : "")
    return sign + fmtPrice(abs(value), market: market, isIndex: isIndex)
}

/// Session volume: "12.4M" / "834k" shares. Traders read volume by order of magnitude, so an exact
/// digit count would be noise.
func fmtVolume(_ shares: Double) -> String {
    let v = max(0, shares)
    if v >= 1_000_000_000 { return String(format: "%.2fB", v / 1_000_000_000) }
    if v >= 1_000_000     { return String(format: "%.1fM", v / 1_000_000) }
    if v >= 1000          { return String(format: "%.0fk", v / 1000) }
    return String(format: "%.0f", v)
}

/// "just now" / "2m ago" / "14:31" for the as-of stamp under each row. Anything older than an hour
/// prints the clock time instead of a duration, because "73m ago" is harder to reason about than
/// "13:18" when you're deciding whether the feed is stuck.
func fmtAsOf(_ date: Date, now: Date = Date()) -> String {
    let secs = now.timeIntervalSince(date)
    if secs < 45 { return "just now" }
    if secs < 3600 { return "\(Int(secs / 60))m ago" }
    let f = DateFormatter()
    f.dateFormat = "HH:mm"
    return f.string(from: date)
}

/// Whether a symbol names an index rather than a tradable stock. Indices are formatted with decimals
/// and have no ceiling/floor band, so several places need this test.
func isIndexSymbol(_ symbol: String) -> Bool {
    let s = symbol.uppercased()
    return s.hasSuffix("INDEX") || s == "VN30" || s == "HNX30"
}
