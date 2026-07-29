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

/// A crypto price for the popover. Precision scales with magnitude because the same formatter has to
/// serve BTC at ~68,000 and a token at 0.00004: two decimals read as "0.00" there, which is useless.
func fmtCryptoPrice(_ value: Double) -> String {
    let f = NumberFormatter()
    f.numberStyle = .decimal
    f.groupingSeparator = ","
    f.decimalSeparator = "."
    switch abs(value) {
    case 1000...:    f.maximumFractionDigits = 0
    case 1..<1000:   f.maximumFractionDigits = 2
    case 0.01..<1:   f.maximumFractionDigits = 4
    default:         f.maximumFractionDigits = 8
    }
    return f.string(from: NSNumber(value: value)) ?? String(value)
}

/// The compact price for the MENU BAR, where every pixel is contested. Crypto is abbreviated with a
/// k/M suffix ("64.1k" for BTC at 64,134); a VN index is rounded to whole points ("1705"), since the
/// decimals cost two characters to tell you something the percentage next to it already conveys.
///
/// VN equity prices are divided by 1000 and shown as e.g. "54.6" — that is how prices are quoted
/// conversationally in Vietnam, and it saves three characters per ticker. Note the threshold is
/// applied to the value AFTER dividing: comparing the raw VND figure against 10,000 sent every normal
/// ticker down the "%.0f" branch and rendered VCB's 54,600 VND as "55" instead of "54.6".
func fmtMenuBarPrice(_ value: Double, market: Market, isIndex: Bool) -> String {
    if market == .vietnam {
        if isIndex { return String(format: "%.0f", value) }        // VN-Index: 1705
        let thousands = value / 1000
        // One decimal is the norm (54.6); a triple-digit price drops it so the item can't grow to
        // "1234.5" wide for a single ticker.
        return String(format: thousands < 100 ? "%.1f" : "%.0f", thousands)
    }
    // Crypto. The bands are chosen so no rendering exceeds 6 characters: a k/M suffix above 10,000,
    // whole units in the 1,000–10,000 range (ETH at 1895.46 reads "1895" — the cents there are noise
    // at menu-bar size and cost two characters), and decimals only where they carry the value.
    let a = abs(value)
    if a >= 1_000_000 { return String(format: "%.2fM", value / 1_000_000) }
    if a >= 10_000    { return String(format: "%.1fk", value / 1000) }
    if a >= 1000      { return String(format: "%.0f", value) }
    if a >= 1         { return String(format: "%.2f", value) }
    return String(format: "%.4f", value)
}

/// The signed percentage shown next to the price, e.g. "+0.82%" / "−1.14%". Uses U+2212 MINUS SIGN
/// rather than a hyphen so the negative sign has the same width as the plus in a monospaced-digit
/// font — with a hyphen the label visibly shifts every time a quote crosses zero.
func fmtChangePercent(_ pct: Double) -> String {
    let sign = pct > 0 ? "+" : (pct < 0 ? "\u{2212}" : "")
    return sign + String(format: "%.2f%%", abs(pct))
}

/// The menu-bar variant: one decimal instead of two. The menu bar is read at a glance to answer "up or
/// down, and roughly how much" — the second decimal costs a character per pinned symbol and answers
/// nothing at that size. The popover keeps two decimals for when the exact figure matters.
func fmtChangePercentCompact(_ pct: Double) -> String {
    let sign = pct > 0 ? "+" : (pct < 0 ? "\u{2212}" : "")
    return sign + String(format: "%.1f%%", abs(pct))
}

/// The signed absolute change, in the same display unit as the price.
func fmtChange(_ value: Double, market: Market, isIndex: Bool) -> String {
    let sign = value > 0 ? "+" : (value < 0 ? "\u{2212}" : "")
    let magnitude = abs(value)
    if market == .vietnam {
        return sign + fmtVNPrice(magnitude, isIndex: isIndex)
    }
    return sign + fmtCryptoPrice(magnitude)
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
