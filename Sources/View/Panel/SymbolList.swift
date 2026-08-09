// SymbolList.swift — the watched symbols, one row each, plus the controls that appear beside a row while
// the list is being edited.
//
// This is the only part of the panel that scrolls (TickerPopover decides when). Everything else stays
// pinned, so Refresh, the add field and Quit remain reachable however long the list grows.

import SwiftUI
import AppKit
import Combine

struct SymbolList: View {
    @ObservedObject var reader: QuoteReader
    @ObservedObject var watchlist: Watchlist
    let editing: Bool

    /// The row whose detail card is open, if any — see `detailIsShown`. Set by clicking a row, and the card
    /// then stays put until it is dismissed, which is the whole difference from the hover it replaced: the
    /// card can be read without holding the pointer still on the row it belongs to.
    @State private var selected: String?

    /// The row whose editor strip is open, if any. One at a time: two open strips push the list around
    /// enough that the row being aimed at moves out from under the pointer.
    ///
    /// Seeded from the environment for the same reason `selected` is — Tools/uisnap.sh cannot press a
    /// button, and a state that cannot be rendered cannot be checked. Never set for the app itself.
    @State private var expanded: String? = ProcessInfo.processInfo.environment["STOCKBAR_UI_EDITOR"]

    /// Forces one symbol's card open so Tools/uisnap.sh can render it. A click is unreachable from a
    /// snapshot tool, and an unrenderable state is an unverifiable one. Never set for the app itself.
    private static let forcedCard = ProcessInfo.processInfo.environment["STOCKBAR_UI_CARD"]?.uppercased()

    var body: some View {
        // spacing 0 with the gap moved into each entry's own padding, so every row's click target reaches
        // its neighbour's. With the gap between them there was 10pt of dead space between rows where a
        // click hit nothing at all — and a click that does nothing reads as a broken panel, not as a miss.
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

                    if editing {
                        alertButton(entry)
                        removeButton(entry)
                    }
                }
                .padding(.vertical, Theme.Space.rowGap / 2)
                // The row is mostly Spacer, and a click on a transparent area is not reported without this.
                .contentShape(Rectangle())
                .onTapGesture { toggle(entry) }
                // The card itself is drawn by the panel, not from here — see DetailCardOverlay. This row
                // only says that it is the one that was clicked, and hands over a rectangle the panel can
                // resolve into a position.
                .detailAnchor(entry, when: detailIsShown(entry))

                // Outside the HStack above, so the strip gets the full panel width and does not inherit
                // the row's tap gesture — a click meant for a text field must not also toggle a card.
                if editing, expanded == entry.id {
                    RowEditor(reader: reader, watchlist: watchlist, entry: entry)
                        .padding(.bottom, Theme.Space.rowGap / 2)
                }
            }
        }
        // Edit mode suppresses the card (see detailIsShown), so a selection made before it was entered would
        // reappear on the way out — a card opening by itself, minutes after the click that asked for it.
        // The editor strip closes with it, which is also what commits a field left mid-edit: RowEditor
        // writes back in `onDisappear`.
        .onChange(of: editing) { _ in selected = nil; expanded = nil }
        // Same reasoning across an open/close of the whole panel: the popover's view tree is built once and
        // outlives every showing of it, so without this the panel reopens with the card that was on screen
        // when it was last dismissed. The notification is the only signal the panel gets — NSPopover is
        // owned by AppDelegate and nothing about its state reaches down here.
        .onReceive(NotificationCenter.default.publisher(for: NSPopover.didCloseNotification)) { _ in
            selected = nil
        }
    }

    /// Click the row whose card is open to close it, any other row to move the card there.
    ///
    /// Toggling rather than only opening matters because the card is the only thing a click on a row does:
    /// with no way to close it from the same place it was opened, dismissing it would mean closing the whole
    /// panel.
    private func toggle(_ entry: WatchedSymbol) {
        selected = (selected == entry.id) ? nil : entry.id
    }

    /// Whether `entry`'s card is open.
    ///
    /// The card floats over the panel and takes no clicks of its own (see DetailCardOverlay), so clicking
    /// where it is drawn reaches the row underneath and moves the card there. That follows from the card
    /// being an annotation rather than a window, and it is why the rows' click targets have to be
    /// contiguous: whatever the card covers is still the thing a click is aimed at.
    ///
    /// Suppressed while editing: a card over the reorder chevrons would cover the control being clicked
    /// towards, and a list being rearranged is not a list anyone is reading valuation ratios off.
    private func detailIsShown(_ entry: WatchedSymbol) -> Bool {
        guard !editing else { return false }
        return selected == entry.id || Self.forcedCard == entry.symbol.uppercased()
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
    /// The order matters beyond the list: the menu bar renders pinned symbols in watchlist order — four
    /// at a time, rotating through the rest — so reordering is also how you choose who leads the cycle.
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

    /// Opens the editor strip, and doubles as the indicator that a row has thresholds on it: the bell is
    /// filled and tinted whenever any are set, so edit mode alone answers "which rows will interrupt me".
    private func alertButton(_ entry: WatchedSymbol) -> some View {
        let armed = !entry.alerts.isEmpty
        return Button { expanded = (expanded == entry.id) ? nil : entry.id } label: {
            Image(systemName: armed ? "bell.fill" : "bell")
                .font(Theme.Fonts.pinIcon)
                .foregroundStyle(armed ? Color.accentColor : .secondary)
        }
        .buttonStyle(.plain)
        .help(armed ? "Edit the price alerts" : "Add a price alert")
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
