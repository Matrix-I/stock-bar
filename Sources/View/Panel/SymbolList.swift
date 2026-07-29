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

    var body: some View {
        VStack(spacing: Theme.Space.rowGap) {
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
            }
        }
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
