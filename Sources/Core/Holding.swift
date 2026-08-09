// Holding.swift — how much of a row you own and what you paid, which turns a price into a position.
//
// A ticker answers "what is it worth"; a holding answers "what is it worth to me". The arithmetic is
// three multiplications and a subtraction, and it is in Core anyway for the reason everything here is:
// the answer is a number nobody can check by looking at it. A profit computed against the wrong basis, or
// in the wrong unit, is still a plausible figure in the right currency.
//
// UNITS ARE THE INSTRUMENT'S OWN, throughout, which is what keeps this arithmetic honest without any
// conversion in it. Quantity is shares for a HOSE equity, coins for a Binance pair, lượng for the gold
// bar; average cost is in whatever `Quote.price` is quoted in for that row, so cost, value and profit all
// come out in the same currency the row already shows. Nothing here mixes two.
//
// THERE IS DELIBERATELY NO PORTFOLIO TOTAL. Summing these would mean adding dong to dollars, and the only
// honest way to do that is to convert — which the app can now do, since USDVND is a row it carries. But a
// total is a different feature with a different failure mode (one stale rate quietly re-pricing everything
// you own), and a per-row profit is useful on its own in a way half a total is not.

import Foundation

struct Holding: Codable, Sendable, Hashable {

    /// Units held, in the instrument's own unit. Fractional on purpose: a crypto position is rarely a
    /// whole coin, and a gold position is rarely a whole lượng.
    var quantity: Double
    /// Average cost per unit, in the same unit `Quote.price` is quoted in for this row.
    var averageCost: Double

    /// Nothing worth storing. A row whose holding is empty carries nil rather than a pair of zeros, so the
    /// detail card can ask one question instead of three.
    var isEmpty: Bool { quantity <= 0 && averageCost <= 0 }

    /// What the position cost. Zero when no average cost has been entered, which is a real state: someone
    /// may want the position size on screen before they get round to digging out what they paid.
    var costBasis: Double { quantity * averageCost }

    func marketValue(at price: Double) -> Double { quantity * price }

    /// Unrealised profit. nil rather than a number when there is no basis to measure against — with a cost
    /// of zero the "profit" is the whole market value, which would render as a spectacular gain on a
    /// position whose cost simply hasn't been typed in yet.
    func profit(at price: Double) -> Double? {
        guard quantity > 0, averageCost > 0 else { return nil }
        return marketValue(at: price) - costBasis
    }

    /// The same figure against what it cost, which is the one a position is actually judged by: a million
    /// dong up means nothing until you know whether it was staked against ten or a thousand.
    func profitPercent(at price: Double) -> Double? {
        guard let profit = profit(at: price), costBasis > 0 else { return nil }
        return profit / costBasis * 100
    }
}
