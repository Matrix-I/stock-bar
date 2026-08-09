// DerivedQuote.swift — the rows this app computes instead of fetching.
//
// Every other quote in the app is something a feed said. This one is arithmetic over three of them: what a
// lượng of SJC costs, minus what the same weight of world spot gold costs once converted through the dollar
// rate. Vietnamese papers print it daily as "chênh lệch giá vàng", and no endpoint publishes it, because it
// is a number about two markets and neither of them owns it.
//
// Kept in Core, as pure functions over a dictionary of quotes, for the reason everything else is: the
// conversion has three chances to be wrong by a factor (a weight, a currency, a thousand), all three would
// still render a plausible-looking figure, and a plausible wrong number is exactly what a test catches and
// a screenshot does not.
//
// A DERIVED ROW PULLS ITS INPUTS INTO THE FETCH PLAN. Watching GOLDGAP without watching GOLD, SJC and
// USDVND has to work — otherwise the row is a dash until the user guesses which three other rows to add,
// with nothing on screen to say so. `tracked(_:)` is what QuoteReader plans against; the extra entries are
// fetched and cached but never drawn, because the panel iterates the watchlist rather than this list.

import Foundation

enum DerivedQuote {

    /// The one derived row. A `switch` over symbols rather than a table of closures: there is exactly one
    /// of these, its inputs and its arithmetic are specific to it, and a general expression engine would be
    /// more machinery than the thing it computes.
    static let goldGap = "GOLDGAP"

    static func isDerived(_ symbol: String) -> Bool {
        Ticker.canonical(symbol) == goldGap
    }

    /// The rows `symbol` needs before it can be computed. Empty for everything that is fetched normally.
    static func inputs(for symbol: String) -> [WatchedSymbol] {
        guard isDerived(symbol) else { return [] }
        return [
            WatchedSymbol(symbol: "SJC", market: .vietnam, pinnedToMenuBar: false),
            WatchedSymbol(symbol: "GOLD", market: .world, pinnedToMenuBar: false),
            WatchedSymbol(symbol: "USDVND", market: .vietnam, pinnedToMenuBar: false),
        ]
    }

    /// `watched` plus whatever its derived rows depend on, de-duplicated by id and with the user's own
    /// entries winning — an input that is also watched keeps its pin and its position rather than being
    /// replaced by the unpinned copy above.
    static func tracked(_ watched: [WatchedSymbol]) -> [WatchedSymbol] {
        var out = watched
        var seen = Set(watched.map(\.id))
        for entry in watched {
            for input in inputs(for: entry.symbol) where !seen.contains(input.id) {
                seen.insert(input.id)
                out.append(input)
            }
        }
        return out
    }

    /// Compute every derived row in `watched` from the quotes already fetched, keyed by `WatchedSymbol.id`
    /// exactly as `QuoteReader` holds them. A row whose inputs have not all arrived yet is simply absent,
    /// which leaves it on a dash rather than on a number computed from two thirds of an equation.
    static func values(for watched: [WatchedSymbol], from quotes: [String: Quote]) -> [String: Quote] {
        var out: [String: Quote] = [:]
        for entry in watched where isDerived(entry.symbol) {
            if let value = goldGap(from: quotes) { out[entry.id] = value }
        }
        return out
    }

    // MARK: - The gap

    /// SJC's selling price minus world spot gold converted to VND per lượng.
    ///
    /// Three conversions, each one a chance to be wrong by a constant:
    ///
    ///   • WEIGHT. XAU/USD is a price per troy ounce (31.1034768 g) and SJC is priced per lượng (37.5 g),
    ///     so the world price buys 1.2057 ounces' worth before the two are comparable. Dropping this makes
    ///     the gap look about twenty percent too wide, which is still a believable-looking premium.
    ///   • CURRENCY. Vietcombank's selling rate, matching the side of the sheet the press converts at.
    ///   • UNIT. Both sides end in real VND per lượng; PNJQuoteSource has already lifted the jeweller's
    ///     thousands-of-dong-per-chỉ into that unit, so there is no factor of ten thousand left here.
    ///
    /// `asOf` is the OLDEST of the three inputs, not the newest and not the clock. The gap is only as
    /// current as its stalest ingredient — on a Sunday the world price is minutes old and the gold board is
    /// from Saturday morning, and the honest answer is Saturday morning.
    ///
    /// No reference, so no change figure: PNJ publishes no previous close, so any baseline for this would
    /// have to be invented. See the note in DomesticIndex.
    /// The world spot price expressed in what SJC is priced in: VND per lượng. Public because the gap's
    /// detail card shows the subtraction it was born from, and a card computing this conversion its own
    /// way is two chances for the same formula to disagree with itself.
    static func worldPerLuong(spotUSD: Double, usdVND: Double) -> Double {
        spotUSD * GoldUnit.troyOuncesPerLuong * usdVND
    }

    private static func goldGap(from quotes: [String: Quote]) -> Quote? {
        guard let sjc = quotes["vietnam:SJC"],
              let world = quotes["world:GOLD"],
              let rate = quotes["vietnam:USDVND"],
              sjc.price > 0, world.price > 0, rate.price > 0 else { return nil }

        let worldPerLuong = worldPerLuong(spotUSD: world.price, usdVND: rate.price)
        return Quote(
            symbol: goldGap,
            market: .vietnam,
            price: sjc.price - worldPerLuong,
            reference: nil,
            ceiling: nil,
            floor: nil,
            volume: nil,
            asOf: min(sjc.asOf, world.asOf, rate.asOf)
        )
    }
}
