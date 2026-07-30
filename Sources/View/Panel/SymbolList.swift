// SymbolList.swift — the watched symbols, one row each, plus the controls that appear beside a row while
// the list is being edited.
//
// This is the only part of the panel that scrolls (TickerPopover decides when). Everything else stays
// pinned, so Refresh, the add field and Quit remain reachable however long the list grows.

import SwiftUI

struct SymbolList: View {
    @ObservedObject var reader: QuoteReader
    @ObservedObject var watchlist: Watchlist
    let editing: Bool

    /// The row the pointer is resting on, if any — see `detailIsShown`.
    @State private var hovered: String?

    /// Forces one symbol's card open so Tools/uisnap.sh can render it. Hover is unreachable from a snapshot
    /// tool, and an unrenderable state is an unverifiable one. Never set for the app itself.
    private static let forcedHover = ProcessInfo.processInfo.environment["STOCKBAR_UI_HOVER"]?.uppercased()

    var body: some View {
        // spacing 0 with the gap moved into each entry's own padding, so the hit areas the hover is
        // measured against are CONTIGUOUS. With the gap between them, crossing from one row to the next
        // passed through 10pt of dead space and the open card blinked shut and back on the way.
        VStack(spacing: 0) {
            ForEach(Array(watchlist.symbols.enumerated()), id: \.element.id) { index, entry in
                VStack(alignment: .leading, spacing: Theme.Space.detailGap) {
                    HStack(spacing: Theme.Space.control) {
                        if editing {
                            pinButton(entry)
                            reorderButtons(entry, at: index)
                        }

                        QuoteRow(entry: entry,
                                 quote: reader.quotes[entry.id],
                                 history: reader.history[entry.id] ?? [],
                                 stale: reader.isStale(entry.id),
                                 showSparkline: !editing)

                        if editing { removeButton(entry) }
                    }

                    if detailIsShown(entry) {
                        QuoteDetailCard(rows: QuoteDetail.rows(for: entry,
                                                               quote: reader.quotes[entry.id],
                                                               fundamentals: reader.fundamentals[entry.id] ?? .none))
                    }
                }
                .padding(.vertical, Theme.Space.rowGap / 2)
                // The row is mostly Spacer, and hover is not reported for transparent areas without this.
                .contentShape(Rectangle())
                .onHover { inside in
                    if inside {
                        hovered = entry.id
                    } else if hovered == entry.id {
                        // Guarded: the pointer entering the next row reports that one's `true` before this
                        // one's `false`, and clearing unconditionally would then close the card that just
                        // opened.
                        hovered = nil
                    }
                }
            }
        }
    }

    /// Whether `entry`'s card is open. The card is attached to the entry's whole stack rather than to the
    /// quote row, which is what lets the pointer move down INTO the card without the hover ending and the
    /// card vanishing from under it.
    ///
    /// Suppressed while editing: the card would push the reorder chevrons around under the pointer, and a
    /// list being rearranged is not a list anyone is reading valuation ratios off.
    private func detailIsShown(_ entry: WatchedSymbol) -> Bool {
        guard !editing else { return false }
        return hovered == entry.id || Self.forcedHover == entry.symbol.uppercased()
    }

    private func pinButton(_ entry: WatchedSymbol) -> some View {
        Button { watchlist.togglePinned(entry) } label: {
            Image(systemName: entry.pinnedToMenuBar ? "pin.fill" : "pin.slash")
                .font(Theme.Fonts.pinIcon)
                .foregroundStyle(entry.pinnedToMenuBar ? Color.accentColor : .secondary)
        }
        .buttonStyle(.plain)
        .help(entry.pinnedToMenuBar ? "Hide from the menu bar" : "Show in the menu bar")
    }

    /// Reorder. Stacked vertically so the pair costs one button's width instead of two — this row
    /// already carries a symbol, a price and two other buttons.
    ///
    /// The order matters beyond the list: the menu bar renders pinned symbols in watchlist order and
    /// keeps the first four, so reordering is also how you choose which pinned symbols get a slot.
    private func reorderButtons(_ entry: WatchedSymbol, at index: Int) -> some View {
        VStack(spacing: 0) {
            reorderButton("chevron.up", disabled: index == 0) { watchlist.moveUp(entry) }
            reorderButton("chevron.down", disabled: index == watchlist.symbols.count - 1) {
                watchlist.moveDown(entry)
            }
        }
    }

    /// One half of the up/down control. Disabled rather than hidden at the ends of the list, so the rows
    /// stay aligned instead of shifting sideways on the first and last entry.
    private func reorderButton(_ symbol: String, disabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(Theme.Fonts.reorderIcon)
                .frame(width: Theme.Size.reorderHit.width, height: Theme.Size.reorderHit.height)
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .foregroundStyle(disabled ? Color.secondary.opacity(Theme.Opacity.disabledIcon) : .secondary)
        .help(symbol == "chevron.up" ? "Move up" : "Move down")
    }

    private func removeButton(_ entry: WatchedSymbol) -> some View {
        Button { watchlist.remove(entry) } label: {
            Image(systemName: "minus.circle.fill")
                .font(Theme.Fonts.removeIcon)
                .foregroundStyle(.red)
        }
        .buttonStyle(.plain)
    }
}
