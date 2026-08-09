// QuoteRow.swift — one watched symbol: ticker and venue, an intraday sparkline, price and change.

import SwiftUI

struct QuoteRow: View {
    let entry: WatchedSymbol
    let quote: Quote?
    let history: [Double]
    let stale: Bool
    /// Dropped while the watchlist is being edited. The edit controls (pin, up, down, remove) claim real
    /// width, and keeping the chart alongside them truncated the change line to "+24.06 (+…" on the index
    /// rows and wrapped it onto a second line on the others, making the rows different heights. The chart
    /// is the least useful thing on screen while you're reordering a list, so it yields.
    var showSparkline = true

    var body: some View {
        HStack(spacing: Theme.Space.columns) {
            symbolColumn

            if let quote {
                if showSparkline {
                    Sparkline(values: history, color: BandStyle.color(quote.band, market: quote.market))
                        .frame(width: Theme.Size.sparkline.width, height: Theme.Size.sparkline.height)
                }

                Spacer(minLength: Theme.Space.priceGutter)

                priceColumn(quote)
            } else {
                Spacer()
                Text("—").foregroundStyle(.secondary).font(Theme.Fonts.noData)
            }
        }
        .opacity(stale ? Theme.Opacity.stale : 1)
    }

    private var symbolColumn: some View {
        VStack(alignment: .leading, spacing: Theme.Space.tight) {
            Text(entry.symbol.uppercased())
                .font(Theme.Fonts.symbol)
                .lineLimit(1)
            HStack(spacing: Theme.Space.tight) {
                Text(entry.venueLabel)
                    .font(Theme.Fonts.venue)
                    .foregroundStyle(.secondary)
                // A row that will interrupt you should say so without being clicked. On the venue line
                // rather than beside the price, because the price column is the one thing here that must
                // keep its width — a glyph appearing next to it would shift every digit sideways the
                // moment a threshold was set.
                if !entry.alerts.isEmpty {
                    Image(systemName: "bell.fill")
                        .font(Theme.Fonts.venue)
                        .foregroundStyle(.secondary)
                        .help(alertSummary)
                }
            }
        }
        .frame(width: Theme.Size.symbolColumn, alignment: .leading)
    }

    /// The tooltip behind the bell: what is set, and whether it has already had its say. "fired" rather
    /// than a silent disarmed state, because an alert that has gone off looks identical to one that never
    /// will, and the difference is the whole reason arming is persisted.
    private var alertSummary: String {
        entry.alerts
            .sorted { $0.direction.rawValue < $1.direction.rawValue }
            .map { alert in
                let level = PriceFormat.price(alert.threshold, market: entry.market, isIndex: entry.isIndex)
                return "\(alert.holdsDescription) \(level)\(alert.isArmed ? "" : " (fired)")"
            }
            .joined(separator: " · ")
    }

    private func priceColumn(_ quote: Quote) -> some View {
        let tint = BandStyle.color(quote.band, market: quote.market)
        return VStack(alignment: .trailing, spacing: Theme.Space.tight) {
            // Deliberately NOT .textSelection(.enabled), which this used to be. The whole row is a click
            // target now — clicking it opens the detail card — and selectable text inside a click target
            // claims the mouse-down for a drag-selection of its own. The price is the largest thing in the
            // row and the most natural place to aim at, so leaving it selectable would have made the app's
            // one gesture fail exactly where it is most likely to be tried.
            Text(PriceFormat.price(quote.price, market: quote.market, isIndex: entry.isIndex))
                .font(Theme.Fonts.price)
                .monospacedDigit()
                .foregroundStyle(tint)
            if let pct = quote.changePercent, let chg = quote.change {
                Text("\(quote.band.arrow) \(PriceFormat.change(chg, market: quote.market, isIndex: entry.isIndex)) (\(PriceFormat.percent(pct)))")
                    .font(Theme.Fonts.change)
                    .monospacedDigit()
                    .foregroundStyle(tint.opacity(Theme.Opacity.change))
                    // Never wrap or ellipsise: this line is the whole point of the row, and a second
                    // line would make neighbouring rows different heights.
                    .lineLimit(1)
                    .fixedSize()
            }
        }
    }

}
