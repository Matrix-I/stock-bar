// Portfolio.swift — every position added up, in one currency.
//
// This is the first thing in the app that ADDS TWO ROWS TOGETHER. Everything else formats one row at a
// time, where the unit is whatever the feed said and never has to be named; a total cannot do that, so it
// is also the first thing that can be wrong in a way no single row could be. Two rules follow, and both
// are about refusing rather than computing.
//
// IT CONVERTS THROUGH A ROW THE USER CAN SEE. Dollars become dong at the app's own USDVND — the same
// number drawn on its own row, from Vietcombank's published sheet — and not at a rate fetched privately
// for this calculation. A total priced off an invisible rate is a total nobody can check, and a wrong one
// is more confidently wrong than any row it is made of. No USDVND, no conversion: the dong holdings still
// total, and the panel says how many rows were left out.
//
// IT LEAVES OUT WHAT IT CANNOT ACCOUNT FOR, AND COUNTS EVERY ONE. Three separate ways a held row falls
// short of being addable, and none of them may pass silently — a total quietly missing a position is the
// failure this whole file is arranged against, because it reads as a complete answer:
//
//   • NO CURRENCY THIS APP CAN CONVERT. The Nikkei prints in yen and there is no yen rate; a Yahoo listing
//     outside the world table may print in anything at all. Both are `excluded`.
//   • NO PRICE YET. A holding whose quote has not arrived — a feed down, a symbol that answers for nobody —
//     is not a position worth zero, it is a position this app cannot value. `unpriced`.
//   • NO COST ENTERED. Its value is known and belongs in the total; its RETURN is not known and must not be
//     invented. It counts toward `value` and toward `withoutBasis`, and stays out of `measured` and `cost`.
//
// THE RETURN IS MEASURED OVER A SUBSET, WHICH IS WHY THERE ARE TWO VALUES. `value` is everything that could
// be priced and converted; `measured` is the part of it that has a cost to be judged against. They are
// equal for every portfolio where each position has a basis, which is the normal case. They are not equal
// the moment somebody types a quantity and leaves the cost for later — and adding that position's market
// value to `value` while adding zero to `cost` would have reported its entire worth as profit. That is
// exactly the lie `Holding.profit` returns nil to avoid, and it survived a level up by arithmetic rather
// than by intent: the `cost > 0` guard below only fires when NO position has a basis, so one basis-less row
// mixed with one real one rendered a spectacular green percentage on a portfolio that had merely not been
// filled in yet.
//
// ON THE PROFIT FIGURE: both the value and the cost convert at TODAY's rate, so the percentage is the
// instrument's own move expressed in dong, with the currency's move factored out. The alternative — cost
// converted at the rate on the day of purchase — is the more complete answer and needs a purchase date
// and a rate history this app does not have. What is here is the honest subset, and the header of
// Holding.swift says the same thing about a position's own arithmetic.

import Foundation

struct Portfolio: Sendable, Equatable {

    /// Market value of everything that could be priced and converted, in VND.
    let value: Double
    /// The part of `value` that has a stated cost behind it, and therefore a return worth quoting. Equal
    /// to `value` unless a position is missing its average cost.
    let measured: Double
    /// What that subset cost, in VND, converted at the same rate — see the header.
    let cost: Double
    /// How many rows carried a position in a currency this app could not convert: yen, a listing whose
    /// unit nothing here can name, or dollars with no USDVND to convert them through.
    let excluded: Int
    /// How many rows carried a position whose quote has not arrived, so it could not be valued at all.
    let unpriced: Int
    /// How many rows are counted in `value` but stand outside the return, because no average cost has been
    /// entered for them yet.
    let withoutBasis: Int
    /// The oldest input that went into it, the dollar rate included. A total is exactly as current as its
    /// stalest ingredient, and on a weekend that is the gold board from Saturday morning rather than the
    /// crypto tick from a second ago.
    let asOf: Date

    /// Measured against `measured` and never against `value`: a position with no cost contributes to what
    /// the portfolio is WORTH and can contribute nothing to what it has MADE.
    var profit: Double { measured - cost }

    /// nil when nothing was staked — a percentage against a zero basis is the same lie `Holding` refuses,
    /// one level up.
    var profitPercent: Double? {
        guard cost > 0 else { return nil }
        return profit / cost * 100
    }

    /// Sum every position in `entries`.
    ///
    /// nil when nothing convertible was held at all, which the panel draws as no line rather than as a
    /// total of zero — a zero would claim the user owns nothing, and the truth is that nobody has said.
    static func total(for entries: [WatchedSymbol], quotes: [String: Quote]) -> Portfolio? {
        // The dollar rate is looked up by id like any other row, because that is what it is: the total
        // converts through the same USDVND the panel draws, not through a rate of its own.
        let usdVND = quotes["vietnam:USDVND"].map(\.price).flatMap { $0 > 0 ? $0 : nil }

        var value = 0.0
        var measured = 0.0
        var cost = 0.0
        var excluded = 0
        var unpriced = 0
        var withoutBasis = 0
        var counted = 0
        var oldest: Date?
        var usedRate = false

        for entry in entries {
            guard let holding = entry.holding, !holding.isEmpty, holding.quantity > 0 else { continue }
            // Held, but nothing to value it at. Counted rather than skipped: it was a real position a
            // moment ago and it will be one again, and in between the total is short by it.
            guard let quote = quotes[entry.id] else { unpriced += 1; continue }

            let rate: Double
            // The feed's own word first, the table second. Only the feed can speak for a symbol the table
            // has never heard of, and it is the one answer that cannot disagree with the price it came in.
            switch quote.currency ?? Currency.of(symbol: entry.symbol, market: entry.market) {
            case .vnd:
                rate = 1
            case .usd:
                guard let usdVND else { excluded += 1; continue }
                rate = usdVND
                usedRate = true
            case .jpy:
                // No yen rate anywhere in this app. Counted and dropped, never guessed at.
                excluded += 1
                continue
            case nil:
                // Nothing named this row's unit — an unlisted world listing whose feed stayed quiet, or a
                // coin-quoted crypto pair. Treated exactly as an unconvertible currency, because that is
                // what it is: a number whose unit is unknown cannot be added to one whose unit is dong.
                excluded += 1
                continue
            }

            counted += 1
            value += holding.marketValue(at: quote.price) * rate
            oldest = oldest.map { min($0, quote.asOf) } ?? quote.asOf

            // Worth something, and worth an unknown amount MORE OR LESS than it cost. The value stands;
            // the return abstains. See the header for what including it would have printed.
            guard holding.averageCost > 0 else { withoutBasis += 1; continue }
            measured += holding.marketValue(at: quote.price) * rate
            cost += holding.costBasis * rate
        }

        guard counted > 0 else { return nil }
        // The rate is an ingredient, so its own age bounds the total's — a fresh crypto tick converted
        // through Friday's sheet is a Friday number.
        if usedRate, let rateAsOf = quotes["vietnam:USDVND"]?.asOf {
            oldest = oldest.map { min($0, rateAsOf) } ?? rateAsOf
        }
        return Portfolio(value: value, measured: measured, cost: cost, excluded: excluded,
                         unpriced: unpriced, withoutBasis: withoutBasis, asOf: oldest ?? Date())
    }
}
