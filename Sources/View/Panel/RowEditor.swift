// RowEditor.swift — the strip that opens under a row in edit mode, for the per-row settings that need a
// number typed rather than a button pressed: the price alerts, and the position held.
//
// It exists because a quote row has no room left. The row already carries a ticker, a venue, a chart, a
// price and a change, and edit mode adds four buttons to that; a threshold field squeezed onto the same
// line would push the change figure into an ellipsis, which is the one thing on the row that must never
// truncate. Opening underneath costs a row of height only while it is being used.
//
// Edit mode and not the detail card, even though the card is what a click on a row opens and where the
// position is read back. The card is drawn by the panel as a floating overlay with
// `allowsHitTesting(false)` — clicks pass straight through it to the row underneath, deliberately — so
// nothing inside it can be typed into without unpicking that. Edit mode is also where every other per-row
// setting already lives.

import SwiftUI

struct RowEditor: View {
    @ObservedObject var reader: QuoteReader
    @ObservedObject var watchlist: Watchlist
    let entry: WatchedSymbol

    /// Typed text, kept as strings so a half-finished number does not have to parse. Seeded from what is
    /// stored when the strip opens, and written back on submit or on losing focus.
    @State private var above = ""
    @State private var below = ""
    @State private var quantity = ""
    @State private var cost = ""

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.addMessage) {
            HStack(spacing: Theme.Space.control) {
                label("Alert")
                // `≥` and `≤` rather than the words: two labelled fields plus the row's own label and the
                // panel's padding do not fit across 320pt, and "below" wrapped inside its own label. The
                // symbols also say more precisely what a threshold means than the band arrows would — ▲
                // already means "up on the day" everywhere else in this panel.
                field("≥", text: $above,
                      help: "Notify when the price reaches this or more") {
                    commitAlert($0, direction: .above)
                }
                field("≤", text: $below,
                      help: "Notify when the price reaches this or less") {
                    commitAlert($0, direction: .below)
                }
                Spacer(minLength: 0)
            }

            HStack(spacing: Theme.Space.control) {
                label("Held")
                // `@` is how a position is written down everywhere: 1,200 @ 58,400. Quantity is in the
                // instrument's own unit and cost in its own currency, so nothing here needs a unit label
                // that the row above does not already give.
                field("#", text: $quantity,
                      help: "How many you hold — shares, coins, or lượng") {
                    watchlist.setHoldingQuantity(entry, PriceFormat.parse($0))
                }
                field("@", text: $cost,
                      help: "Average cost per unit") {
                    watchlist.setHoldingCost(entry, PriceFormat.parse($0))
                }
                Spacer(minLength: 0)
            }

            // Said here rather than left to be discovered, because it is invisible until it fails. There is
            // no server behind this app: an alert is only checked when a poll happens, and a poll only
            // happens while the row's own venue is open and the app is running. A HOSE threshold cannot fire
            // at two in the morning however far the price would have moved by then.
            Text(note)
                .font(Theme.Fonts.warning)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.leading, Theme.Space.control)
        .onAppear(perform: load)
    }

    private var note: String {
        entry.market == .crypto
            ? "Alerts are checked once a minute while StockBar is running."
            : "Alerts are checked once a minute while StockBar is running and \(entry.venueLabel) is open."
    }

    private func label(_ text: String) -> some View {
        Text(text)
            .font(Theme.Fonts.detailLabel)
            .foregroundStyle(.secondary)
            // Fixed, so the two rows of fields line up under each other rather than each starting wherever
            // its own label happens to end.
            .frame(width: Theme.Size.editorLabel, alignment: .leading)
    }

    private func field(_ prefix: String, text: Binding<String>, help: String,
                       commit: @escaping (String) -> Void) -> some View {
        HStack(spacing: Theme.Space.tight) {
            Text(prefix)
                .font(Theme.Fonts.field)
                .foregroundStyle(.secondary)
            TextField("—", text: text)
                .help(help)
                .textFieldStyle(.roundedBorder)
                .font(Theme.Fonts.field)
                .monospacedDigit()
                .frame(width: Theme.Size.alertField)
                // Commit on Enter, and again when the field gives up focus — closing the strip by clicking
                // the bell again is at least as likely as pressing Return, and a value that silently failed
                // to save would be worse than one that was never offered.
                .onSubmit { commit(text.wrappedValue) }
                .onDisappear { commit(text.wrappedValue) }
        }
    }

    /// Seeded in the spelling the panel prints, so reopening the strip shows each number the way it will be
    /// read back — and so a value copied from the card above lands here unchanged.
    private func load() {
        above = storedAlert(.above)
        below = storedAlert(.below)
        quantity = entry.holding.map { $0.quantity > 0 ? PriceFormat.quantity($0.quantity) : "" } ?? ""
        cost = entry.holding.map {
            $0.averageCost > 0 ? PriceFormat.price($0.averageCost, market: entry.market,
                                                   isIndex: entry.isIndex) : ""
        } ?? ""
    }

    private func storedAlert(_ direction: PriceAlert.Direction) -> String {
        guard let alert = entry.alerts.first(where: { $0.direction == direction }) else { return "" }
        return PriceFormat.price(alert.threshold, market: entry.market, isIndex: entry.isIndex)
    }

    /// An empty field clears that direction's alert; anything unparseable is left alone rather than
    /// silently dropped, so a typo does not quietly remove a threshold that was working.
    private func commitAlert(_ text: String, direction: PriceAlert.Direction) {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty {
            reader.setAlert(entry, direction: direction, threshold: nil)
            return
        }
        guard let value = PriceFormat.parse(trimmed), value > 0 else { return }
        reader.setAlert(entry, direction: direction, threshold: value)
    }
}
