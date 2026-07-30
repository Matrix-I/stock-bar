// DetailCardLayout.swift — where the floating detail card goes.
//
// The card used to be laid out in the flow, directly under the row it annotates. Opening it pushed every
// row below it downwards, which moved the very prices the reader was aiming the pointer at, and on the
// last row it grew the whole popover. It now floats over the panel's content instead — which means its
// position is no longer something the layout system works out. It has to be computed, and this is the
// computation, kept out of the view so the awkward cases can be stated as tests rather than discovered on
// screen.
//
// The card is going to cover SOMETHING: the panel is one narrow column and there is nowhere else to put it.
// The order of preference is what this file encodes — cover rows before chrome, and never cover the row
// being described.

import Foundation

enum DetailCardLayout {

    /// A vertical stretch of the panel, in the panel's own coordinate space.
    struct Span: Equatable, Sendable {
        let top: CGFloat
        let bottom: CGFloat
    }

    /// The y of the card's top edge.
    ///
    /// Tried in three tiers:
    ///
    ///   1. Inside `list` — under the row, or above it when the bottom of the list is too close. A card
    ///      among the rows covers other rows, which is the same kind of thing it is, and leaves the pinned
    ///      header and footer alone. This is what happens for all but the last row or two of any list long
    ///      enough to be worth scrolling.
    ///   2. Inside `panel`, which means over the footer. The list can simply be shallower than the card is
    ///      tall — three watched symbols and a Vietnamese equity's seven rows — and then covering the
    ///      settings block for as long as the pointer rests is better than covering the price being read.
    ///   3. Clamped into `panel`. Needs a window barely taller than the card; keeps it on screen.
    ///
    /// - Parameters:
    ///   - rowTop: the hovered row's top edge, its padding included — the card hangs off the hover target
    ///     rather than off the text, so the gap looks the same above and below.
    ///   - rowBottom: that row's bottom edge, likewise.
    ///   - cardHeight: the card's measured height. Zero on the very first pass, before it has been laid
    ///     out; the caller keeps the card invisible until then rather than placing it on a guess.
    ///   - gap: between the row and the card.
    ///   - margin: how close to a span's edge the card may come. The popover has rounded corners and a
    ///     shadow of its own, and a card flush against that edge reads as clipped.
    static func top(rowTop: CGFloat, rowBottom: CGFloat, cardHeight: CGFloat,
                    list: Span, panel: Span, gap: CGFloat, margin: CGFloat) -> CGFloat {
        if let y = fit(rowTop: rowTop, rowBottom: rowBottom, cardHeight: cardHeight,
                       in: list, gap: gap, margin: margin) { return y }
        if let y = fit(rowTop: rowTop, rowBottom: rowBottom, cardHeight: cardHeight,
                       in: panel, gap: gap, margin: margin) { return y }
        // Prefer the top edge, so the part that survives is the one with the labels on it.
        return max(panel.top + margin, min(rowBottom + gap, panel.bottom - margin - cardHeight))
    }

    /// Below the row if the card fits there, above it if it fits there, otherwise nowhere in this span.
    ///
    /// Below first because that is where the eye already is, having just read the row. The flip is what the
    /// bottom row of the list gets — and the bottom row is one of the most hovered in any list, being the
    /// one someone has just added.
    private static func fit(rowTop: CGFloat, rowBottom: CGFloat, cardHeight: CGFloat,
                            in span: Span, gap: CGFloat, margin: CGFloat) -> CGFloat? {
        let below = rowBottom + gap
        if below + cardHeight + margin <= span.bottom { return below }

        let above = rowTop - gap - cardHeight
        if above >= span.top + margin { return above }

        return nil
    }
}
