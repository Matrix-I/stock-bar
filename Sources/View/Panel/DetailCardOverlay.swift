// DetailCardOverlay.swift — draws the clicked row's detail card OVER the panel instead of inside it.
//
// The card used to be a view inside the row's own stack, which made opening it a layout change: the
// rows below slid down, and on the last row the popover itself grew. Reading a price is aiming at a number,
// and the card moved the numbers.
//
// So it is drawn by an ancestor now, and this file is the seam. Two problems the row itself cannot solve
// are the reason it has to be an ancestor:
//
//   1. A row inside a ScrollView cannot draw outside it. The card has to be able to overlap the header, the
//      footer and the rows either side of its own, and the scroll view would clip all of that.
//   2. A row does not know where it is. Placing the card needs the row's position in the panel and the
//      panel's height — and while the list is scrolled, the row's position is not even a constant.
//
// SwiftUI's answer to both is an anchor preference: the row publishes a rectangle it cannot resolve, and
// the ancestor resolves it in its own coordinate space, scroll offset already accounted for.

import SwiftUI

/// The row whose card is open, on its way up the tree.
///
/// `Anchor` is a deferred rectangle — it carries no numbers a child could read, only enough for an
/// ancestor's `GeometryProxy` to turn it into one. That is what makes this safe to publish from inside a
/// scroll view.
struct DetailAnchor {
    let entry: WatchedSymbol
    let bounds: Anchor<CGRect>
}

enum DetailAnchorKey: PreferenceKey {
    static let defaultValue: DetailAnchor? = nil

    /// At most one row is selected, so there is nothing to merge: every other row offers nil and the first
    /// real value stands. `value ?? nextValue()` rather than the other way round so that a value already
    /// collected is never dropped by a later nil.
    static func reduce(value: inout DetailAnchor?, nextValue: () -> DetailAnchor?) {
        value = value ?? nextValue()
    }
}

extension View {
    /// Offer this row to the panel as the one to annotate. Attach it to the row's whole click target,
    /// padding included, so the card's gap is measured from the edge of what was clicked.
    func detailAnchor(_ entry: WatchedSymbol, when shown: Bool) -> some View {
        anchorPreference(key: DetailAnchorKey.self, value: .bounds) { bounds in
            shown ? DetailAnchor(entry: entry, bounds: bounds) : nil
        }
    }
}

struct DetailCardOverlay: View {
    @ObservedObject var reader: QuoteReader
    let anchor: DetailAnchor?

    /// Where the symbol list sits inside the panel: its top edge, and the height of the chrome pinned below
    /// it. The card is kept inside that stretch where it can be, so that what it covers is other rows rather
    /// than the settings block — see DetailCardLayout. Both are measurements the panel already has and a row
    /// has no way of knowing.
    let listTop: CGFloat
    let listBottomInset: CGFloat

    /// The card's own height, which its placement depends on: whether there is room below the row is a
    /// question about how tall the card is. It cannot be known before the card has been laid out, so the
    /// first pass measures it at `top`'s unmeasured answer and keeps it invisible — one frame of nothing
    /// rather than one frame of a card in the wrong place.
    ///
    /// It deliberately survives the card closing. The next click then places the card correctly on its
    /// first pass, because consecutive cards are nearly always the same height.
    @State private var cardHeight: CGFloat = 0

    var body: some View {
        GeometryReader { proxy in
            if let anchor {
                let row = proxy[anchor.bounds]
                QuoteDetailCard(rows: rows(for: anchor.entry))
                    // The panel's own inset, so the card lines up with the rows it annotates rather than
                    // with the window.
                    .frame(width: proxy.size.width - Theme.Space.panelH * 2)
                    .measuringHeight(into: $cardHeight)
                    .offset(x: Theme.Space.panelH,
                            y: DetailCardLayout.top(
                                rowTop: row.minY,
                                rowBottom: row.maxY,
                                cardHeight: cardHeight,
                                list: DetailCardLayout.Span(top: listTop,
                                                            bottom: proxy.size.height - listBottomInset),
                                panel: DetailCardLayout.Span(top: 0, bottom: proxy.size.height),
                                gap: Theme.Space.detailGap,
                                margin: Theme.Space.detailMargin))
                    .opacity(cardHeight > 0 ? 1 : 0)
            }
        }
        // Not optional. This overlay covers the entire panel, so with hit testing on, its GeometryReader
        // would swallow the click that opens the card in the first place, and every click meant for a row.
        // Off, it is what it looks like: an annotation drawn on top, with the row underneath still the thing
        // being clicked. The cost is that a click on the card reaches the row it covers and moves the card
        // there — which is consistent, if surprising the first time; the alternative is an overlay that eats
        // clicks, and that failure is silent and total.
        .allowsHitTesting(false)
    }

    private func rows(for entry: WatchedSymbol) -> [QuoteDetail.Row] {
        QuoteDetail.rows(for: entry,
                         quote: reader.quotes[entry.id],
                         fundamentals: reader.fundamentals[entry.id] ?? .none,
                         // The whole cache, for the one card that shows its working: the gap's inputs are
                         // other rows' quotes, fetched for it whether or not they are watched.
                         context: reader.quotes)
    }
}
