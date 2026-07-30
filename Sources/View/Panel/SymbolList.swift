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
                // The card itself is drawn by the panel, not from here — see DetailCardOverlay. This row
                // only says that it is the one being pointed at, and hands over a rectangle the panel can
                // resolve into a position.
                .detailAnchor(entry, when: detailIsShown(entry))
            }
        }
    }

    /// Whether `entry`'s card is open.
    ///
    /// The card floats over the panel and takes no hover of its own, so "into the card" is not a place the
    /// pointer can go: moving down from a row lands on the next row, whose card takes over. That is the
    /// behaviour to want — the card annotates wherever the pointer is — and it is the reason the rows'
    /// hit areas have to be contiguous.
    ///
    /// Suppressed while editing: a card over the reorder chevrons would cover the control the pointer is on
    /// its way to, and a list being rearranged is not a list anyone is reading valuation ratios off.
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
