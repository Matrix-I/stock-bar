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
            Text(entry.venueLabel)
                .font(Theme.Fonts.venue)
                .foregroundStyle(.secondary)
        }
        .frame(width: Theme.Size.symbolColumn, alignment: .leading)
    }

    private func priceColumn(_ quote: Quote) -> some View {
        let tint = BandStyle.color(quote.band, market: quote.market)
        return VStack(alignment: .trailing, spacing: Theme.Space.tight) {
            Text(PriceFormat.price(quote.price, market: quote.market, isIndex: entry.isIndex))
                .font(Theme.Fonts.price)
                .monospacedDigit()
                .foregroundStyle(tint)
                .textSelection(.enabled)
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
