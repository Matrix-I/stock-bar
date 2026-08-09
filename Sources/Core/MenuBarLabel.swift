// MenuBarLabel.swift — everything the menu-bar image is drawn from, derived from the watchlist and the
// quote cache. Pure: it produces strings and bands, never colours or images.
//
// The point of the type is that it is `Equatable`. The glyph is expensive to build (real text
// measurement plus CG drawing) and is rebuilt ~1 Hz, so the caller has to skip the ticks where nothing
// visible changed. That used to be a hand-assembled cache-key string — every field that affects the
// drawing had to be remembered into it, and a field left out means a glyph that never updates. Here the
// value IS the key: if two labels are equal, the same image would be drawn.
//
// `isDark` is part of the value for that reason too. A coloured image cannot be a template, so the glyph
// bakes its own neutral text colour and would otherwise not re-tint when the system theme flips.

import Foundation

/// One symbol's worth of text for the menu bar, already resolved to strings.
struct MenuBarEntry: Equatable, Sendable {
    let label: String          // "VNI", "BTC"
    let price: String          // "1,704.68", "64,134.01"
    let change: String?        // "+1.43%" — nil when the change is unknown or the user hid it
    /// The band the price is coloured by; nil for a pinned symbol with no quote, which is drawn neutral.
    let band: PriceBand?
    let market: Market
    /// Draw dimmed: the quote is older than it should be.
    let stale: Bool
}

struct MenuBarLabel: Equatable, Sendable {
    let entries: [MenuBarEntry]
    /// The appearance the neutral parts are baked for — see the file header.
    let isDark: Bool

    /// The most pinned rows the bar draws at once. The cap used to silently discard everything past the
    /// fourth pin; now it only bounds what shows simultaneously, and the overflow rotates through. The
    /// number itself is unchanged, and for the same reason as ever: more at once pushes the app's own
    /// item off the far left of a crowded menu bar, where macOS truncates it without saying so.
    static let maxVisible = 4

    /// How long each rotation step holds. Long enough to read every price in the window at a glance,
    /// short enough that eight pinned symbols cycle in about a minute — the same order of time as the
    /// data refresh, so nothing shown is a full cycle stale by the time it comes round again.
    static let rotationInterval: TimeInterval = 8

    /// The slice of `pinned` the bar should show at `offset` rotation steps.
    ///
    /// With `maxVisible` or fewer pinned this is the identity, whatever the offset — the common case
    /// keeps today's behaviour exactly, static and free of churn. Past that, a wrapping window advances
    /// one symbol per step: the leftmost drops off and the next pinned row joins on the right, so each
    /// symbol stays readable for `maxVisible` consecutive steps rather than blinking in and out.
    ///
    /// Pure in `offset` so the schedule stays out of Core: the caller derives it from the wall clock,
    /// and a test hands in whatever step it wants to assert on. Negative-safe because a caller counting
    /// from an arbitrary epoch may legitimately be behind it.
    static func visibleWindow(of pinned: [WatchedSymbol], at offset: Int) -> [WatchedSymbol] {
        guard pinned.count > maxVisible else { return pinned }
        let start = ((offset % pinned.count) + pinned.count) % pinned.count
        return (0..<maxVisible).map { pinned[(start + $0) % pinned.count] }
    }

    /// Build the label for the pinned rows.
    ///
    /// `staleIDs` is passed in rather than computed here because staleness depends on the wall clock,
    /// and a value that changes with `Date()` cannot be compared for equality or asserted on in a test.
    static func make(pinned: [WatchedSymbol],
                     quotes: [String: Quote],
                     staleIDs: Set<String>,
                     showChange: Bool,
                     isDark: Bool) -> MenuBarLabel {
        let entries = pinned.map { entry -> MenuBarEntry in
            guard let quote = quotes[entry.id] else {
                // A pinned symbol with no quote still gets a row. Skipping it meant a symbol that failed
                // to fetch vanished from the menu bar completely, which is indistinguishable from it
                // never having been pinned — the user sees a missing ticker and blames the pin, not the
                // feed. A dash says "pinned, no data", which is the truth.
                return MenuBarEntry(label: entry.menuBarLabel, price: "—", change: nil,
                                    band: nil, market: entry.market, stale: true)
            }
            return MenuBarEntry(
                label: entry.menuBarLabel,
                // The SAME formatters the popover uses, so the menu bar and the panel can never
                // disagree about what an instrument costs.
                price: PriceFormat.price(quote.price, market: quote.market, isIndex: entry.isIndex),
                // Each pinned symbol's percentage costs ~45pt of menu bar. Users with a crowded menu bar
                // (or many pinned symbols) can trade it away for width; the popover always shows it.
                change: showChange ? quote.changePercent.map(PriceFormat.percent) : nil,
                band: quote.band,
                market: quote.market,
                stale: staleIDs.contains(entry.id)
            )
        }
        return MenuBarLabel(entries: entries, isDark: isDark)
    }

    /// Nothing is pinned — the state the menu bar answers with the app's mark instead of text.
    ///
    /// Not the same as "no data", and the difference is load-bearing: a pinned symbol whose fetch has
    /// never succeeded still gets an entry (see `make`), so an empty `entries` can only mean an empty
    /// watchlist. If this ever became true for a failed fetch as well, a symbol the user pinned would
    /// disappear behind the mark and the app would look idle rather than broken.
    var hasNothingPinned: Bool { entries.isEmpty }

    /// What VoiceOver reads for the status item.
    var accessibilityDescription: String {
        // "No quotes yet" was wrong about its own state — with nothing pinned there is nothing to quote,
        // and with something pinned there is always an entry to read out, dash or not.
        guard !hasNothingPinned else { return "StockBar, nothing pinned" }
        return entries
            .map { "\($0.label) \($0.price)\($0.change.map { c in ", \(c)" } ?? "")" }
            .joined(separator: "; ")
    }
}
