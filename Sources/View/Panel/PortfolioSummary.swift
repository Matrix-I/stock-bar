// PortfolioSummary.swift — one line under the list: what everything held is worth, and what it has made.
//
// Absent entirely when nothing is held, which is most watchlists and the shipped default. A ticker is
// useful without a portfolio, and a row reading "Portfolio —" would be chrome asking to be filled in.
//
// Pinned rather than scrolled, at the top of the footer. A total belongs with the session line and the
// controls, not at the bottom of a list that may be twenty rows long: the number that answers "how am I
// doing" should not need scrolling to.

import SwiftUI

struct PortfolioSummary: View {
    let portfolio: Portfolio
    /// Drawn dimmed when the total's oldest ingredient is old enough that the rows would be dimmed too —
    /// passed in rather than computed here for the same reason `MenuBarLabel` takes its stale set: the
    /// wall clock has no business inside a view's body.
    var stale = false

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.tight) {
            HStack(spacing: Theme.Space.control) {
                Text("Portfolio")
                    .font(Theme.Fonts.settingsLabel)
                    .foregroundStyle(.secondary)

                Spacer(minLength: Theme.Space.switchGap)

                Text(PriceFormat.price(portfolio.value, market: .vietnam, isIndex: false))
                    .font(Theme.Fonts.settingsLabel)
                    .monospacedDigit()

                if let percent = portfolio.profitPercent {
                    // The same arrow, colour and U+2212 the rows use, so a gain reads the same here as on
                    // the row it came from. A band rather than a bare sign, because that carries the colour.
                    let band: PriceBand = portfolio.profit > 0 ? .up
                        : (portfolio.profit < 0 ? .down : .unchanged)
                    Text("\(band.arrow) \(PriceFormat.percent(percent))")
                        .font(Theme.Fonts.settingsStatus)
                        .monospacedDigit()
                        .foregroundStyle(BandStyle.color(band, market: .vietnam))
                        .lineLimit(1)
                        .fixedSize()
                }
            }

            // Never silent about a position it could not add. A total quietly missing a row is the one
            // failure this line must not have — it would read as a complete answer and be a partial one.
            if portfolio.excluded > 0 {
                Text(excludedNote)
                    .font(Theme.Fonts.warning)
                    .foregroundStyle(.orange)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .opacity(stale ? Theme.Opacity.stale : 1)
        .help("Converted to VND at the USDVND rate on the panel. USDT is counted as one dollar.")
    }

    private var excludedNote: String {
        let n = portfolio.excluded
        return "\(n) position\(n == 1 ? "" : "s") left out — no rate to convert \(n == 1 ? "it" : "them")."
    }
}
