// QuoteDetail.swift — the label/value pairs shown when the pointer rests on a row.
//
// This is what the row's `.help()` tooltip used to say, in three respects changed: it appears at once
// instead of after AppKit's one-to-two-second delay, it is in English throughout (the tooltip mixed in
// Trần/Sàn/TC, which only helps a reader who already knows what a Vietnamese board looks like), and it
// carries the two valuation ratios.
//
// The strings live here rather than in the view so the set of rows for each kind of instrument is
// something a test can state: an index has no daily band and no earnings, a crypto pair has neither a
// band nor a reference close, and a row with no quote yet has nothing to show at all.

import Foundation

enum QuoteDetail {

    struct Row: Equatable, Identifiable, Sendable {
        /// The label is unique within a card, which is what makes it usable as the identity.
        var id: String { label }
        let label: String
        let value: String
    }

    /// Everything worth saying about one watched row, in reading order: where the price sits in its
    /// permitted band, what the market is paying for the earnings and the book, how much traded, and how
    /// old the reading is.
    ///
    /// Empty when there is no quote — the caller says so in its own words rather than being handed a row
    /// that is really a message.
    static func rows(for entry: WatchedSymbol,
                     quote: Quote?,
                     fundamentals: Fundamentals = .none,
                     now: Date = Date()) -> [Row] {
        guard let quote else { return [] }
        var rows: [Row] = []

        func price(_ value: Double, isIndex: Bool = false) -> String {
            PriceFormat.price(value, market: quote.market, isIndex: isIndex)
        }

        // The daily band, which only a Vietnamese equity has. These are the numbers a VN trader wants the
        // moment a stock locks up, and the reason the tooltip existed in the first place.
        if let ceiling = quote.ceiling { rows.append(Row(label: "Ceiling", value: price(ceiling))) }
        if let floor = quote.floor { rows.append(Row(label: "Floor", value: price(floor))) }

        if let reference = quote.reference {
            // Three baselines, three words for them. A venue that never closes has no previous close, so
            // Binance quotes its change against the price 24 hours ago on a rolling window; a VN board
            // publishes a reference price the band is cut from; a world index simply closed yesterday.
            let label: String
            switch quote.market {
            case .vietnam: label = "Reference"
            case .crypto:  label = "24h open"
            case .world:   label = "Prev close"
            }
            rows.append(Row(label: label, value: price(reference, isIndex: entry.isIndex)))
        }

        // The session's traded extremes, two rows and not one "low–high" range. That was tried: a crypto
        // range ("64,730.08–65,192.54") is wider than a card column, and neither wrapping (a double-height
        // row knocking the two columns out of line) nor shrinking (still ellipsised at 0.75×) survived
        // contact with it. Two rows fit at any magnitude, and it is how a Vietnamese board prints the pair
        // anyway. High first, matching those boards. Crypto's labels name the window, because its "session"
        // is a rolling day and an unlabelled extreme next to a "24h open" invites the wrong comparison.
        if let high = quote.high {
            rows.append(Row(label: quote.market == .crypto ? "24h high" : "High",
                            value: price(high, isIndex: entry.isIndex)))
        }
        if let low = quote.low {
            rows.append(Row(label: quote.market == .crypto ? "24h low" : "Low",
                            value: price(low, isIndex: entry.isIndex)))
        }

        // Where the day's business was actually done, volume-weighted. Only the VN board computes one; it
        // answers whether the current print is above or below the crowd's average fill.
        if let average = quote.average {
            rows.append(Row(label: "Avg price", value: price(average, isIndex: entry.isIndex)))
        }

        if let volume = quote.volume { rows.append(Row(label: "Volume", value: PriceFormat.volume(volume))) }

        // Khối ngoại: net foreign buying, in shares, signed. The one number on a Vietnamese board that
        // this card was missing entirely — the session's direction is routinely read off it.
        if let net = quote.foreignNet {
            rows.append(Row(label: "Foreign", value: PriceFormat.netVolume(net)))
        }

        // Volume goes ABOVE the ratios, which reads a little oddly here and is right on screen. The card
        // fills its first column and then its second, so with all seven rows present a P/E left at position
        // four lands at the foot of the left column while P/B starts the right one — splitting the one pair
        // in the card that is read as a pair. One row earlier and the two sit together.
        //
        // Gated on the market as well as at the fetch: a crypto pair has no earnings and no book, so
        // whatever might end up in the dictionary against its id, this is not the place it becomes a
        // valuation. Keeping the invariant local means it holds however the caller is wired.
        if quote.market == .vietnam {
            if let pe = fundamentals.priceEarnings(at: quote.price) {
                rows.append(Row(label: "P/E", value: PriceFormat.ratio(pe)))
            }
            if let pb = fundamentals.priceBook(at: quote.price) {
                rows.append(Row(label: "P/B", value: PriceFormat.ratio(pb)))
            }
        }

        // The position, if there is one. Last before the timestamp because these are the only rows about
        // the reader rather than about the instrument — everything above is true for anyone looking at this
        // ticker, and everything here is true for exactly one person.
        //
        // Kept together as a block, which the card's fill order preserves: it fills the first column and
        // then the second, so four consecutive rows either sit together or split once, never interleave
        // with the valuation ratios above them.
        if let holding = entry.holding, !holding.isEmpty {
            if holding.quantity > 0 {
                rows.append(Row(label: "Qty", value: PriceFormat.quantity(holding.quantity)))
            }
            if holding.averageCost > 0 {
                rows.append(Row(label: "Avg cost",
                                value: price(holding.averageCost, isIndex: entry.isIndex)))
            }
            if holding.quantity > 0 {
                rows.append(Row(label: "Value",
                                value: price(holding.marketValue(at: quote.price), isIndex: entry.isIndex)))
            }
            // Both halves or neither: a profit without the percentage begs the question it exists to
            // answer, and the percentage alone hides the size of the position it is a percentage of.
            if let profit = holding.profit(at: quote.price),
               let percent = holding.profitPercent(at: quote.price) {
                let signed = PriceFormat.change(profit, market: quote.market, isIndex: entry.isIndex)
                rows.append(Row(label: "P/L", value: "\(signed) (\(PriceFormat.percent(percent)))"))
            }
        }

        rows.append(Row(label: "Updated", value: PriceFormat.asOf(quote.asOf, now: now)))

        return rows
    }
}
