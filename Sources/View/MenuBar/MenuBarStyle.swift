// MenuBarStyle.swift — the design tokens for the menu-bar label.
//
// Separate from Theme because the glyph is drawn with AppKit, not SwiftUI: it needs NSFont and NSColor,
// and it is NOT scaled by Theme.scale — the menu bar has a fixed 22pt height set by the system, so the
// panel's 1.5× factor would simply overflow it.

import AppKit

enum MenuBarStyle {
    /// Monospaced digits are load-bearing, not cosmetic: with proportional digits the whole item changes
    /// width on almost every refresh, so every other menu-bar item to its left visibly jumps once a
    /// minute.
    static let priceFont = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium)
    static let tickerFont = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .semibold)

    /// The menu bar gives us 22 points of height; 16 is the usable band for text once the standard
    /// padding is accounted for.
    static let height: CGFloat = 16

    /// A stale row is drawn at reduced alpha rather than in a different hue: the colour still has to mean
    /// up/down, so "old" has to be encoded on a different axis than colour.
    static let staleAlpha: CGFloat = 0.45
    /// The ticker is quieter than the price it labels.
    static let tickerAlpha: CGFloat = 0.75
    static let placeholderAlpha: CGFloat = 0.5

    static let separator = "  "
    static let placeholder = "— —"

    /// The neutral text colour. Read from the appearance rather than left to the system because a
    /// coloured image cannot be a template, so nothing auto-tints it — see MenuBarGlyph.
    static func neutral(isDark: Bool) -> NSColor { isDark ? .white : .black }
}

extension NSApplication {
    /// Whether the app is currently rendering in dark mode. Folded into `MenuBarLabel` so the glyph is
    /// rebuilt on a theme switch.
    var isDarkAppearance: Bool {
        effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
    }
}
