// RowEditor.swift — the strip that opens under a row in edit mode, for the per-row settings that need a
// number typed rather than a button pressed.
//
// It exists because a quote row has no room left. The row already carries a ticker, a venue, a chart, a
// price and a change, and edit mode adds four buttons to that; a threshold field squeezed onto the same
// line would push the change figure into an ellipsis, which is the one thing on the row that must never
// truncate. Opening underneath costs a row of height only while it is being used.
//
// Edit mode and not the detail card, even though the card is what a click on a row opens. The card is
// drawn by the panel as a floating overlay with `allowsHitTesting(false)` — clicks pass straight through
// it to the row underneath, deliberately — so nothing inside it can be typed into without unpicking that.
// Edit mode is also where every other per-row setting already lives.

import SwiftUI

struct RowEditor: View {
    @ObservedObject var reader: QuoteReader
    let entry: WatchedSymbol

    /// Typed text, kept as strings so a half-finished number does not have to parse. Seeded from the stored
    /// alerts when the strip opens, and written back on submit or on losing focus.
    @State private var above = ""
    @State private var below = ""

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.addMessage) {
            HStack(spacing: Theme.Space.control) {
                Text("Alert")
                    .font(Theme.Fonts.detailLabel)
                    .foregroundStyle(.secondary)

                // `≥` and `≤` rather than the words: two labelled fields plus the word "Alert" and the
                // panel's own padding do not fit across 320pt, and "below" wrapped onto a second line
                // inside its own label. The symbols also say more precisely what the threshold means than
                // the band arrows would — ▲ already means "up on the day" everywhere else in this panel.
                field("≥", text: $above, direction: .above)
                field("≤", text: $below, direction: .below)

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
            ? "Checked once a minute while StockBar is running."
            : "Checked once a minute while StockBar is running and \(entry.venueLabel) is open."
    }

    private func field(_ label: String, text: Binding<String>,
                       direction: PriceAlert.Direction) -> some View {
        HStack(spacing: Theme.Space.tight) {
            Text(label)
                .font(Theme.Fonts.field)
                .foregroundStyle(.secondary)
            TextField("—", text: text)
                .help(direction == .above ? "Notify when the price reaches this or more"
                                          : "Notify when the price reaches this or less")
                .textFieldStyle(.roundedBorder)
                .font(Theme.Fonts.field)
                .monospacedDigit()
                .frame(width: Theme.Size.alertField)
                // Commit on Enter, and again when the field gives up focus — closing the strip by clicking
                // the bell again is at least as likely as pressing Return, and a threshold that silently
                // failed to save would be worse than one that was never offered.
                .onSubmit { commit(text.wrappedValue, direction: direction) }
                .onDisappear { commit(text.wrappedValue, direction: direction) }
        }
    }

    private func load() {
        above = stored(.above)
        below = stored(.below)
    }

    /// The stored threshold as text, formatted the way the panel prints prices, so reopening the strip
    /// shows the number in the spelling it will be read back in.
    private func stored(_ direction: PriceAlert.Direction) -> String {
        guard let alert = entry.alerts.first(where: { $0.direction == direction }) else { return "" }
        return PriceFormat.price(alert.threshold, market: entry.market, isIndex: entry.isIndex)
    }

    /// An empty field clears that direction's alert; anything unparseable is left alone rather than
    /// silently dropped, so a typo does not quietly remove a threshold that was working.
    private func commit(_ text: String, direction: PriceAlert.Direction) {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty {
            reader.setAlert(entry, direction: direction, threshold: nil)
            return
        }
        guard let value = PriceFormat.parse(trimmed), value > 0 else { return }
        reader.setAlert(entry, direction: direction, threshold: value)
    }
}
