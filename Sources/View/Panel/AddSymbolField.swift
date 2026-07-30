// AddSymbolField.swift — the market picker, the ticker field, and the check that runs before a symbol is
// allowed into the watchlist.
//
// The list used to accept anything typed into it. A misspelled ticker is not rejected by the upstreams —
// the VN board just omits the row and Binance answers 400 — so it landed in the watchlist and rendered a
// dash indefinitely, which looks identical to a feed that is down. The one moment the difference can
// still be explained is here, before the row exists.
//
// All the state that only this interaction needs lives here rather than in TickerPopover: the typed
// symbol, the chosen market, whether a check is in flight, and the message when one comes back negative.

import SwiftUI

struct AddSymbolField: View {
    @ObservedObject var reader: QuoteReader
    @ObservedObject var watchlist: Watchlist

    @State private var symbol = ""
    @State private var market: Market = .vietnam
    /// A check is in flight. Blocks a second Add so one Enter-mash can't fire several checks.
    @State private var checking = false
    /// Why the last Add didn't go through, shown under the field. nil while there is nothing to say.
    /// Seeded from the environment because the message only appears in response to a rejected click,
    /// which Tools/uisnap.sh cannot perform, and an unrenderable state is an unverifiable one. Never set
    /// for the app itself.
    @State private var message: String? = ProcessInfo.processInfo.environment["STOCKBAR_UI_ADD_ERROR"]

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.addMessage) {
            HStack(spacing: Theme.Space.control) {
                Picker("", selection: $market) {
                    Text("VN").tag(Market.vietnam)
                    Text("Crypto").tag(Market.crypto)
                    Text("World").tag(Market.world)
                }
                .labelsHidden()
                .frame(width: Theme.Size.marketPicker)

                // Typing clears the last verdict: leaving "XYZ isn't listed" under a field that now reads
                // something else accuses the wrong symbol. Done through the binding rather than
                // .onChange(of:perform:), which is deprecated, while its replacement is macOS 14+.
                TextField(Self.placeholder(for: market),
                          text: Binding(get: { symbol },
                                        set: { symbol = $0; message = nil }))
                    .textFieldStyle(.roundedBorder)
                    .font(Theme.Fonts.field)
                    .onSubmit(add)
                    // Deliberately NOT disabled while a check runs: disabling a focused text field drops
                    // the focus ring, so a rejected symbol would leave the caret gone and the field
                    // needing another click before it could be corrected. `add` guards instead.

                if checking {
                    ProgressView()
                        .scaleEffect(Theme.spinnerScale)
                        .frame(width: Theme.Size.spinner, height: Theme.Size.spinner)
                }

                Button("Add", action: add)
                    .disabled(checking || symbol.trimmingCharacters(in: .whitespaces).isEmpty)
            }

            if let message {
                Text(message)
                    .font(Theme.Fonts.warning)
                    .foregroundStyle(.orange)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// What the field suggests typing. Three examples for World rather than one, because unlike a HOSE
    /// ticker or a Binance pair, nobody guesses that the Nasdaq is spelled IXIC here.
    private static func placeholder(for market: Market) -> String {
        switch market {
        case .vietnam: return "VCB / VNINDEX"
        case .crypto:  return "BTCUSDT"
        case .world:   return "DJI / IXIC / NI225"
        }
    }

    private func add() {
        // Canonical, not merely upper-cased: "N225" is the Nikkei this app files as NI225, and checking the
        // typed spelling against the list would let the same index in twice under two names.
        let typed = Ticker.canonical(symbol)
        guard !typed.isEmpty, !checking else { return }
        // The ticker itself overrules the picker, so BTCUSDT typed against the "VN" default is checked
        // against Binance rather than being reported as an unlisted Vietnamese equity. See Market.inferred.
        let venue = Market.inferred(for: typed) ?? market

        // Caught here rather than left to Watchlist.add, which drops a duplicate silently — from the
        // field that is indistinguishable from a rejection, with nothing said either way.
        if watchlist.symbols.contains(where: { $0.symbol == typed && $0.market == venue }) {
            message = "\(typed) is already in the list"
            return
        }

        checking = true
        message = nil
        Task {
            let verdict = await reader.validate(typed, market: venue)
            checking = false
            switch verdict {
            case .ok:
                watchlist.add(typed, market: venue)
                symbol = ""
            case .unknown:
                // Named by venue, because "not listed" is only actionable if you know who was asked.
                switch venue {
                case .vietnam:
                    message = "\(typed) isn't listed on HOSE/HNX — check the ticker."
                case .crypto:
                    message = "\(typed) isn't a pair on Binance — check the ticker."
                case .world:
                    message = "\(typed) isn't an index we can fetch — try DJI, IXIC or NI225."
                }
            case .unreachable(let why):
                // Not added. The symbol may well be real, but adding it on an unverified guess is how the
                // permanent-dash row got here in the first place; the message names the check as the thing
                // that failed, and pressing Add again retries it.
                message = "Couldn't check \(typed) — \(why). Try again."
            }
        }
    }
}
