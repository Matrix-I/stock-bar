// Theme.swift — the panel's design tokens: one place that decides how big everything is and which type
// size each kind of text gets.
//
// Two reasons this is a namespace rather than numbers at the call sites it replaced.
//
// 1. SCALE. The panel renders 50% larger than the system default. Scaling only the fonts clipped the
//    columns — a 66pt symbol column cannot hold "BTCUSDT" at 18pt, and the change line went back to
//    reading "+24.06 (+…" — so widths, padding and spacing all scale with the text. Keeping the base
//    numbers here and multiplying in one function means the ratios between elements stay readable and
//    the factor is a single edit rather than forty.
//
// 2. REUSE. `pt` and the font helpers used to be file-private functions inside TickerPopover.swift,
//    which is why every row, header and footer view had to live in that one 576-line file: moving one
//    out took its sizing with it. Tokens with names are also self-documenting in a way `uiFont(9)` at
//    fourteen different call sites is not — `Theme.Fonts.venue` says which text it is for.
//
// Adding a token is cheaper than adding a literal: a value that appears twice is a value that will
// eventually be changed in one place only. `Space.panelH` in particular is read by the padding AND by
// the scroll-height arithmetic, which is exactly the pair that drifted before.

import SwiftUI

enum Theme {

    /// Everything below multiplies by this.
    static let scale: CGFloat = 1.5

    /// The settings block below the last divider is deliberately a fifth smaller than the rows above it.
    /// It is chrome you set once rather than data you read, and at the panel's scale it was competing
    /// with the prices for attention.
    static let settingsScale: CGFloat = 0.8

    /// A scaled point value, for frames, padding and spacing.
    static func pt(_ value: CGFloat) -> CGFloat { value * scale }

    /// A scaled system font. Sizes are given at their unscaled value so they stay comparable with the
    /// AppKit defaults they were chosen against.
    static func font(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size * scale, weight: weight)
    }

    private static func settingsFont(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        font(size * settingsScale, weight)
    }

    /// A `ProgressView` spinner is sized by scaling, not by frame — it has a fixed intrinsic size.
    static let spinnerScale: CGFloat = 0.6 * scale

    /// How much of the screen the whole panel may occupy before the symbol list starts scrolling instead
    /// of pushing the popover further down.
    static let panelHeightFraction: CGFloat = 0.9

    // MARK: - Spacing

    enum Space {
        /// The panel's own inset. Applied per region rather than to the panel, so the scroll view spans
        /// the full width and its overlay scroller has a gutter of its own — with the padding outside,
        /// the scroller was drawn on top of the change figures.
        static let panelH = Theme.pt(12)
        static let panelV = Theme.pt(12)

        /// Between two symbol rows.
        static let rowGap = Theme.pt(7)
        /// Between the columns within one symbol row.
        static let columns = Theme.pt(10)
        /// Between adjacent controls: the edit buttons beside a row, the fields in the add row, the
        /// session dot and its label.
        static let control = Theme.pt(6)
        /// Above and below a `Divider`.
        static let divider = Theme.pt(6)
        /// Between the blocks of the settings stack.
        static let stack = Theme.pt(6)
        /// The two-line stacks inside a column (ticker over venue, price over change).
        static let tight = Theme.pt(1)
        /// Minimum gap the price column keeps from whatever is to its left.
        static let priceGutter = Theme.pt(4)
        /// Add row to the message under it.
        static let addMessage = Theme.pt(4)
        /// Above the add row, separating it from the list.
        static let addTop = Theme.pt(8)
        /// Minimum gap between a settings label and its switch, so a long label truncates rather than
        /// pushing the switch off the panel.
        static let switchGap = Theme.pt(12)

        /// Between a row and the card floating off it on hover — above or below, so it is read as the gap
        /// on whichever side the card ended up.
        static let detailGap = Theme.pt(4)
        /// How close the floating card may come to the panel's own edge before it is moved. The popover has
        /// rounded corners and a shadow, and a card flush against that edge reads as clipped.
        static let detailMargin = Theme.pt(4)
        /// The floating card's shadow is offset downwards, the direction the light comes from in every other
        /// macOS panel.
        static let cardShadowY = Theme.pt(1)
        /// Inside the detail card: between its two column pairs, and between a label and its value.
        static let detailColumns = Theme.pt(14)
        static let detailLabel = Theme.pt(6)
        static let detailRows = Theme.pt(3)
        static let detailPadding = Theme.pt(7)
    }

    // MARK: - Sizes

    enum Size {
        static let panelWidth = Theme.pt(320)
        /// Fixed so every row's price column starts at the same x, whatever the ticker's length.
        static let symbolColumn = Theme.pt(66)
        static let sparkline = CGSize(width: Theme.pt(78), height: Theme.pt(22))
        static let spinner = Theme.pt(12)
        /// The up/down chevrons are stacked, so each gets half the height of a normal control.
        static let reorderHit = CGSize(width: Theme.pt(11), height: Theme.pt(8))
        static let sessionDot = Theme.pt(6)
        static let marketPicker = Theme.pt(84)
        /// Keeps a few rows visible on a short display rather than letting the footer squeeze the list to
        /// nothing.
        static let minListHeight = Theme.pt(120)
        static let cardRadius = Theme.pt(5)
        /// The floating card's hairline and the blur under it. A card that overlaps the rows below it needs
        /// an edge of its own — without one it reads as a hole in the list rather than as a thing on top
        /// of it.
        static let cardBorder = Theme.pt(0.5)
        static let cardShadow = Theme.pt(5)
    }

    // MARK: - Type

    enum Fonts {
        static let panelTitle = Theme.font(13, .semibold)
        static let version = Theme.font(9)

        static let symbol = Theme.font(12, .semibold)
        static let venue = Theme.font(9)
        static let price = Theme.font(12, .medium)
        static let change = Theme.font(9)
        /// The em dash a row shows before its first quote arrives.
        static let noData = Theme.font(12)

        static let toolbarIcon = Theme.font(10)
        static let pinIcon = Theme.font(9)
        static let removeIcon = Theme.font(10)
        static let reorderIcon = Theme.font(7, .bold)

        static let field = Theme.font(11)
        /// A rejected Add, and a failed fetch.
        static let warning = Theme.font(9)

        static let settingsLabel = Theme.settingsFont(11)
        static let settingsStatus = Theme.settingsFont(10)

        /// The hover card. Smaller than the row it belongs to, so it reads as an annotation of the row
        /// rather than as more rows.
        static let detailLabel = Theme.font(9)
        static let detailValue = Theme.font(9, .medium)
    }

    // MARK: - Opacity

    enum Opacity {
        /// A stale row is dimmed rather than recoloured: the colour still has to mean up/down, so "old"
        /// is encoded on a different axis.
        static let stale: Double = 0.5
        /// The change line sits just under the price it belongs to.
        static let change: Double = 0.85
        /// The fill under a sparkline — enough to read the slope against, not enough to be a shape.
        static let sparklineArea: Double = 0.14
        /// A reorder chevron at the end of the list: disabled, but still occupying its place so the rows
        /// stay aligned.
        static let disabledIcon: Double = 0.3
        // The floating hover card's own colours are NOT here: it is the one surface in the panel that does
        // not follow the appearance, so its fill, text, edge and shadow are a set that has to be read
        // together. They live in Design/CardStyle.swift.
    }

    // MARK: - Sparkline

    enum Chart {
        /// Inset top and bottom so a stroke at an extreme isn't clipped by the frame.
        static let inset = Theme.pt(1)
        static let lineWidth = Theme.pt(1.4)
    }
}
