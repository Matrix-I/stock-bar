// PriceFormat.swift — how a number becomes the text on screen.
//
// Kept in one namespace because the menu-bar glyph and the popover must agree: the same instrument
// reading two different prices depending on where you looked is exactly the bug this replaced. Any
// change to how a price appears belongs here, never at a call site.
//
// Strings only. The colour half of the same job lives in View/Design/BandStyle.swift, which needs
// SwiftUI and AppKit — this file stays Foundation-only so it can live in the pure, tested layer.

import Foundation

enum PriceFormat {

    // MARK: - Prices

    /// A VND price for the popover: grouped thousands, no decimals above 1000 ("62,400"), one decimal
    /// below it so a sub-1000-VND penny stock doesn't collapse to a flat integer. Indices (VN-Index at
    /// ~1,250.36) keep two decimals — that's how every Vietnamese board prints them.
    static func vnPrice(_ value: Double, isIndex: Bool) -> String {
        if isIndex { return grouped(value, fractionDigits: 2) }
        let f = decimalFormatter()
        f.maximumFractionDigits = value < 1000 ? 1 : 0
        return f.string(from: NSNumber(value: value)) ?? String(value)
    }

    /// A world index: grouped thousands and two decimals, the way every board prints them (Dow 51,891.46,
    /// Nikkei 61,867.43). Not routed through `cryptoPrice`, which happens to agree at these magnitudes but
    /// would start adding four and eight decimal places if it were ever handed something small.
    static func worldPrice(_ value: Double) -> String {
        grouped(value, fractionDigits: 2)
    }

    /// A crypto price. Precision scales with magnitude because the same formatter has to serve BTC at
    /// ~64,000 and a token at 0.00004: two decimals read as "0.00" there, which is useless.
    ///
    /// Above 1 the decimals are FIXED at two rather than merely capped. Two reasons: the price is never
    /// rounded away (a BTC tick of 64,134.01 shows its cents), and the rendered width doesn't change when
    /// a price happens to land on a whole number — with a variable count the menu-bar item jitters
    /// sideways every time the cents hit .00.
    static func cryptoPrice(_ value: Double) -> String {
        let f = decimalFormatter()
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
    /// (VN-Index 1704.68 → "1705", BTC 64,134 → "64.0k") while the popover printed the exact figure, so
    /// the same instrument read as two different prices depending on where you looked.
    static func price(_ value: Double, market: Market, isIndex: Bool) -> String {
        switch market {
        case .vietnam: return vnPrice(value, isIndex: isIndex)
        case .crypto:  return cryptoPrice(value)
        case .world:   return worldPrice(value)
        }
    }

    /// Grouped thousands with a fixed number of decimals. The separators are set explicitly rather than
    /// left to the locale: these are exchange prices, and a Vietnamese locale would render the Dow as
    /// "51.891,46" — correct for the locale and unreadable next to the app's other rows.
    private static func grouped(_ value: Double, fractionDigits: Int) -> String {
        let f = decimalFormatter()
        f.minimumFractionDigits = fractionDigits
        f.maximumFractionDigits = fractionDigits
        return f.string(from: NSNumber(value: value)) ?? String(value)
    }

    private static func decimalFormatter() -> NumberFormatter {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.groupingSeparator = ","
        f.decimalSeparator = "."
        return f
    }

    // MARK: - Changes

    /// The signed percentage shown next to the price, e.g. "+0.82%" / "−1.14%". Uses U+2212 MINUS SIGN
    /// rather than a hyphen so the negative sign has the same width as the plus in a monospaced-digit
    /// font — with a hyphen the label visibly shifts every time a quote crosses zero.
    static func percent(_ pct: Double) -> String {
        sign(of: pct) + String(format: "%.2f%%", abs(pct))
    }

    /// The signed absolute change, formatted through `price` so it carries the same precision as the
    /// price it is a delta of.
    static func change(_ value: Double, market: Market, isIndex: Bool) -> String {
        sign(of: value) + price(abs(value), market: market, isIndex: isIndex)
    }

    private static func sign(of value: Double) -> String {
        value > 0 ? "+" : (value < 0 ? "\u{2212}" : "")
    }

    // MARK: - Other columns

    /// A valuation multiple: "12.97", "2.03". Two decimals because that is how every board prints P/E and
    /// P/B, and because the second one is what distinguishes 2.03 from 2.30 at a glance.
    static func ratio(_ value: Double) -> String {
        String(format: "%.2f", value)
    }

    /// Session volume: "12.4M" / "834k" shares. Traders read volume by order of magnitude, so an exact
    /// digit count would be noise.
    static func volume(_ shares: Double) -> String {
        let v = max(0, shares)
        if v >= 1_000_000_000 { return String(format: "%.2fB", v / 1_000_000_000) }
        if v >= 1_000_000     { return String(format: "%.1fM", v / 1_000_000) }
        if v >= 1000          { return String(format: "%.0fk", v / 1000) }
        return String(format: "%.0f", v)
    }

    /// "just now" / "2m ago" / "14:31" for the as-of stamp under each row. Anything older than an hour
    /// prints the clock time instead of a duration, because "73m ago" is harder to reason about than
    /// "13:18" when you're deciding whether the feed is stuck.
    static func asOf(_ date: Date, now: Date = Date()) -> String {
        let secs = now.timeIntervalSince(date)
        if secs < 45 { return "just now" }
        if secs < 3600 { return "\(Int(secs / 60))m ago" }
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f.string(from: date)
    }
}
