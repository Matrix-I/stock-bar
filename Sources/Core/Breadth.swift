// Breadth.swift — how many stocks on a floor are up, down, flat, or have not traded at all.
//
// The index rows had the thinnest cards in the app: a reference, a volume and a timestamp. The number an
// index is actually read for is missing from all of that — an index up four points on ten stocks rising
// and three hundred falling is a different day from one up four points on breadth. Vietnamese boards put
// this at the top of the screen for exactly that reason.
//
// UNTRADED IS ITS OWN COUNT, and that is not pedantry. Of 428 HOSE tickers on the session this was built
// against, 46 had no matched price at all; calling those "đứng giá" would inflate the flat count by three
// quarters and quietly imply a market with far more indecision in it than there was. A board that reports
// three numbers where the feed knows four is a board that is rounding off the truth.
//
// NOTHING HERE FETCHES OR COUNTS BY ITSELF — this is the shape and the arithmetic, and the counting is one
// pass over quotes the reader already has, so a test can walk it without a network.

import Foundation

struct Breadth: Sendable, Equatable {

    /// Which floor these counts cover. The label is drawn, so the card never implies a breadth wider than
    /// the list it was computed from — HOSE breadth under a VN30 row would be a quiet category error.
    let floor: String

    /// Trading above its reference price.
    let up: Int
    let down: Int
    /// Traded, at exactly the reference. The board's tham chiếu.
    let unchanged: Int
    /// No matched price this session at all. Not flat — nobody has said anything about it.
    let untraded: Int

    /// What the whole floor has traded this session, in VND, summed from each constituent's own volume
    /// and its own volume-weighted average price. nil when the board published neither for anybody, which
    /// is the pre-open state.
    ///
    /// Summed rather than fetched because no upstream this app can reach publishes it, and because the
    /// floor's every row is ALREADY in hand: the breadth count downloads all four hundred of them. Three
    /// more numbers out of the same pass cost nothing but this arithmetic.
    ///
    /// Each row contributes `volume × average`, not `volume × lastPrice`. The average is the price the
    /// session's business was actually done at; the last print is where it happens to be standing now, and
    /// multiplying a whole day's volume by it would value the morning at the afternoon's price.
    let tradedValue: Double?

    /// Foreign buying and selling across the floor, in shares. Both sides rather than the net, because a
    /// net near zero can mean a quiet session or two large flows nearly cancelling, and those are not the
    /// same day.
    let foreignBought: Double?
    let foreignSold: Double?

    /// Memberwise, with the session totals defaulted. Written out for the same reason `Quote`'s is: the
    /// counts are the point of this type and the totals ride along, so a caller that only means to state a
    /// breadth should not have to say "and no turnover" three times to do it.
    init(floor: String, up: Int, down: Int, unchanged: Int, untraded: Int,
         tradedValue: Double? = nil, foreignBought: Double? = nil, foreignSold: Double? = nil) {
        self.floor = floor
        self.up = up
        self.down = down
        self.unchanged = unchanged
        self.untraded = untraded
        self.tradedValue = tradedValue
        self.foreignBought = foreignBought
        self.foreignSold = foreignSold
    }

    /// Everything the count covered, traded or not.
    var total: Int { up + down + unchanged + untraded }

    /// Rows that actually printed. The denominator worth quoting a ratio against, since the untraded ones
    /// have no opinion to include.
    var traded: Int { up + down + unchanged }

    /// Advancers over decliners, the one-number summary. nil when nothing has traded — a ratio against an
    /// empty session is not zero, it is unanswerable, and an early-morning board is exactly that.
    var advanceDeclineRatio: Double? {
        guard down > 0 else { return up > 0 ? Double.infinity : nil }
        return Double(up) / Double(down)
    }

    /// The floor whose constituents an index row summarises, or nil where this app cannot honestly match
    /// the two.
    ///
    /// VN30 is the deliberate nil. It is a thirty-stock subset of HOSE, and this app has no membership
    /// list for it — HOSE breadth drawn under a VN30 row would be a quiet category error, a count of four
    /// hundred stocks labelled as if it described thirty. Better no row than a wrong denominator.
    static func floor(for symbol: String) -> String? {
        switch Ticker.canonical(symbol) {
        case "VNINDEX":  return "HOSE"
        case "HNXINDEX": return "HNX"
        default:         return nil
        }
    }

    /// Count one floor from quotes already fetched.
    ///
    /// A quote with no price is `untraded` rather than skipped: the board reports `lastPrice` 0 for a stock
    /// that has not matched, and dropping those rows would make the total silently smaller than the floor
    /// and turn every ratio into one over a shrinking denominator. A quote with no reference is skipped
    /// entirely, because without a baseline there is nothing to be up or down against.
    static func count(floor: String, quotes: [Quote]) -> Breadth {
        var up = 0, down = 0, unchanged = 0, untraded = 0
        var value = 0.0, bought = 0.0, sold = 0.0
        var sawValue = false, sawForeign = false

        for quote in quotes {
            guard let reference = quote.reference, reference > 0 else { continue }

            // The totals are summed over EVERY row with a reference, including the untraded ones — a stock
            // that has not matched contributes a zero to each, which is exactly right and needs no branch.
            if let volume = quote.volume, let average = quote.average, volume > 0, average > 0 {
                value += volume * average
                sawValue = true
            }
            if let b = quote.foreignBought, let s = quote.foreignSold {
                bought += b
                sold += s
                sawForeign = true
            }

            guard quote.price > 0 else { untraded += 1; continue }
            if quote.price > reference { up += 1 }
            else if quote.price < reference { down += 1 }
            else { unchanged += 1 }
        }

        // nil and not zero where the board said nothing at all. Before the open a floor really has traded
        // nothing, and "0" is the honest answer then — but a feed that dropped the fields entirely would
        // produce the same zero, and those two states must not print alike.
        return Breadth(floor: floor, up: up, down: down, unchanged: unchanged, untraded: untraded,
                       tradedValue: sawValue ? value : nil,
                       foreignBought: sawForeign ? bought : nil,
                       foreignSold: sawForeign ? sold : nil)
    }
}
