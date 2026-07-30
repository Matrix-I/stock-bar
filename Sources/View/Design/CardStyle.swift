// CardStyle.swift — the detail card's palette.
//
// One file rather than four tokens in Theme because these values only work as a set: the fill is the app's
// own background colour, which means NOTHING about the card is distinguished by its fill, and the edge and
// the shadow are carrying that job alone. Change one and the card either disappears into the list or starts
// shouting; they have to be read together.
//
// It has been both other things and both were wrong, which is worth recording so it isn't re-litigated. A
// fill of `controlBackgroundColor` is a shade darker than the popover's own background in dark mode — close
// enough that the card read as a slightly-off rectangle rather than as a card. A light fill on both themes
// fixed that by force and cost more: a bright slab most of the panel's width, belonging to nothing around
// it. The card is part of this app, so it is the app's colour, and the hairline is what says where it ends.

import SwiftUI

enum CardStyle {
    /// The window background, one step lighter than the popover's own in dark mode and the same family in
    /// light. Opaque either way, which it has to be — the card covers rows, and a price showing through a
    /// price is the one thing this panel must never do.
    static let surface = Color(nsColor: .windowBackgroundColor)

    /// Follows the appearance, like the rows the card annotates: the labels are the quieter half of each
    /// pair, and the values carry the same weight as a price in the list.
    static let label = Color.secondary
    static let value = Color.primary

    /// Deliberately not a whisper. With the fill matching the app, this line is the entire difference
    /// between a card and a gap, so it is drawn at a strength that survives being on a dark panel — where a
    /// black shadow, which is most of what lifts a card in light mode, contributes almost nothing.
    static let border = Color.primary.opacity(0.3)
    static let shadow = Color.black.opacity(0.4)
}
