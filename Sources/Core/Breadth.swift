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
        for quote in quotes {
            guard let reference = quote.reference, reference > 0 else { continue }
            guard quote.price > 0 else { untraded += 1; continue }
            if quote.price > reference { up += 1 }
            else if quote.price < reference { down += 1 }
            else { unchanged += 1 }
        }
        return Breadth(floor: floor, up: up, down: down, unchanged: unchanged, untraded: untraded)
    }
}
