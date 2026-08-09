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
// IT LEAVES OUT WHAT IT CANNOT CONVERT, AND COUNTS THEM. The Nikkei prints in yen and this app has no yen
// rate. Folding it in as dollars would be a 150-fold error rendering as a plausible number, so a jpy row
// is excluded and reported. `excluded` is not a diagnostic — it is drawn, because a total quietly missing
// a position is the failure this whole file is arranged against.
//
// ON THE PROFIT FIGURE: both the value and the cost convert at TODAY's rate, so the percentage is the
// instrument's own move expressed in dong, with the currency's move factored out. The alternative — cost
// converted at the rate on the day of purchase — is the more complete answer and needs a purchase date
// and a rate history this app does not have. What is here is the honest subset, and the header of
// Holding.swift says the same thing about a position's own arithmetic.

import Foundation

struct Portfolio: Sendable, Equatable {

    /// Market value of everything that could be converted, in VND.
    let value: Double
    /// What that same set cost, in VND, converted at the same rate — see the header.
    let cost: Double
    /// How many rows carried a position that could not be added: an unconvertible currency, or a dollar
    /// holding with no USDVND to convert it through.
    let excluded: Int
    /// The oldest input that went into it, the dollar rate included. A total is exactly as current as its
    /// stalest ingredient, and on a weekend that is the gold board from Saturday morning rather than the
    /// crypto tick from a second ago.
    let asOf: Date

    var profit: Double { value - cost }

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
        var cost = 0.0
        var excluded = 0
        var counted = 0
        var oldest: Date?
        var usedRate = false

        for entry in entries {
            guard let holding = entry.holding, !holding.isEmpty, holding.quantity > 0,
                  let quote = quotes[entry.id] else { continue }

            let rate: Double
            switch Currency.of(symbol: entry.symbol, market: entry.market) {
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
            }

            counted += 1
            value += holding.marketValue(at: quote.price) * rate
            cost += holding.costBasis * rate
            oldest = oldest.map { min($0, quote.asOf) } ?? quote.asOf
        }

        guard counted > 0 else { return nil }
        // The rate is an ingredient, so its own age bounds the total's — a fresh crypto tick converted
        // through Friday's sheet is a Friday number.
        if usedRate, let rateAsOf = quotes["vietnam:USDVND"]?.asOf {
            oldest = oldest.map { min($0, rateAsOf) } ?? rateAsOf
        }
        return Portfolio(value: value, cost: cost, excluded: excluded, asOf: oldest ?? Date())
    }
}
