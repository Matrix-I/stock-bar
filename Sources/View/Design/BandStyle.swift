// BandStyle.swift — the colour half of the design system: which hue a price band is painted in.
//
// Both spellings live here because the menu-bar glyph (AppKit, NSColor) and the popover (SwiftUI, Color)
// must agree. A row that reads purple in the popover and green in the menu bar is worse than either
// alone, and the only way to guarantee they can't drift is one mapping with two renderings of it.

import SwiftUI
import AppKit

enum BandStyle {

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
    static func color(_ band: PriceBand, market: Market) -> Color {
        Color(nsColor: nsColor(band, market: market))
    }

    /// The NSColor half, for the baked menu-bar image.
    ///
    /// The SwiftUI side is derived from THIS one and not the other way round: `NSColor(Color)`
    /// round-trips through the current appearance and loses the dynamic (light/dark-adaptive) behaviour
    /// of the semantic colours, which is exactly what the menu bar needs to keep.
    static func nsColor(_ band: PriceBand, market: Market) -> NSColor {
        switch band {
        case .ceiling:   return market == .vietnam ? .systemPurple : .systemGreen
        case .floor:     return market == .vietnam ? .systemTeal   : .systemRed
        case .up:        return .systemGreen
        case .down:      return .systemRed
        // A VN board paints the reference price yellow. For crypto, "exactly unchanged" is a rounding
        // artefact rather than a real state, so it reads as ordinary secondary text instead of an alarm
        // colour.
        case .unchanged: return market == .vietnam ? .systemYellow : .secondaryLabelColor
        }
    }

    /// A pinned symbol that has no quote yet — neither up nor down, so neither colour would be honest.
    static let noQuoteNSColor: NSColor = .secondaryLabelColor
}
