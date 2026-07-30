// Fundamentals.swift — the two valuation ratios, computed against the price the panel is showing.
//
// The upstream (SSI's iBoard financial-indicator feed) reports `pe` and `pb` ready-made, and this
// deliberately does NOT use them. Its figures are computed against a price of its own: for VCB it
// reported pe 14.2279 on an EPS of 4,210.03, which implies a price of 59,884 — while the board that same
// minute quoted 54,600. Printing 14.23 under a price of 54,600 invites the reader to divide the two, get
// 12.97, and disbelieve the panel. This app already holds the line that one instrument has one price
// everywhere; a ratio derived from a different price breaks that quietly.
//
// So only the per-share figures are kept, and the ratios are recomputed from the live price. EPS comes
// straight from the feed. Book value per share is recovered from the feed's OWN three numbers —
// pe × eps is the price it was working from, and dividing that by pb gives the book value it was working
// from — which is exact arithmetic on one consistent snapshot rather than a second source to disagree
// with.

import Foundation

/// Trailing per-share figures for one equity. Both fields are optional because the feed answers for
/// listed companies only: an index and an unknown ticker both come back empty, and a newly listed
/// company can be missing a full trailing year.
struct Fundamentals: Sendable, Equatable {
    /// Trailing twelve-month earnings per share, in VND.
    let earningsPerShare: Double?
    /// Book value per share, in VND.
    let bookValuePerShare: Double?
    /// The reporting year the trailing figures are drawn from, for the tooltip's own honesty.
    let year: Int?

    /// Nothing usable — what an index or an unlisted ticker resolves to.
    static let none = Fundamentals(earningsPerShare: nil, bookValuePerShare: nil, year: nil)

    var isEmpty: Bool { earningsPerShare == nil && bookValuePerShare == nil }

    /// Price-to-earnings at `price`.
    ///
    /// nil for a loss-making company rather than a negative multiple: "P/E −8.4" is not a number anyone
    /// reads at a glance, and a row that simply omits the ratio is honest about there being no earnings to
    /// divide by.
    func priceEarnings(at price: Double) -> Double? {
        guard let eps = earningsPerShare, eps > 0, price > 0 else { return nil }
        return price / eps
    }

    /// Price-to-book at `price`. Negative equity is possible on paper and just as unreadable as a negative
    /// P/E, so it is omitted on the same grounds.
    func priceBook(at price: Double) -> Double? {
        guard let bvps = bookValuePerShare, bvps > 0, price > 0 else { return nil }
        return price / bvps
    }

    /// Recover book value per share from a vendor's own P/E, EPS and P/B — see the file header.
    ///
    /// A loss-maker is handled correctly without a special case: the vendor reports a negative pe against
    /// its negative eps, and the product is the positive price it used. What cannot be recovered is a pb of
    /// zero, which is how this feed spells "not reported" for its quarterly rows.
    static func bookValuePerShare(pe: Double?, eps: Double?, pb: Double?) -> Double? {
        guard let pe, let eps, let pb, pb > 0 else { return nil }
        let impliedPrice = pe * eps
        guard impliedPrice > 0 else { return nil }
        return impliedPrice / pb
    }
}
