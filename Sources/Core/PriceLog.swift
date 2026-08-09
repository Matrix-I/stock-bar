// PriceLog.swift — the series this app keeps for itself, because three of its rows have none upstream.
//
// SJC, USDVND and GOLDGAP draw no sparkline: a jeweller's board and a bank's rate sheet are step functions
// published a handful of times a day with no history behind them, and the gap is computed rather than
// fetched, so nobody could publish its past even in principle. But the app already looks at all three
// every minute it is running. Writing down what it saw turns "no chart exists" into "a chart builds
// itself", and the gap over TIME is a more interesting number than the gap at one instant — which is what
// the row has been showing all along.
//
// IT RECORDS CHANGES, NOT OBSERVATIONS. A rate sheet polled every minute for eight hours is 480 readings
// of four distinct values; storing them all would fill the buffer with a flat line and push out the actual
// history. Only a price different from the last one recorded is kept, so the buffer holds moves rather
// than minutes and a week fits comfortably in it.
//
// THE X AXIS IS THEREFORE NOT TIME. The sparkline plots points evenly, so what it draws is the sequence of
// distinct prices, not their spacing — three moves in an hour and three moves in three days look alike. For
// a step function that is the honest shape: the thing worth seeing is the staircase, and pretending to
// even sampling would mean inventing readings between the steps.

import Foundation

struct PriceLog: Codable, Sendable, Equatable {

    /// One recorded price and when it was first seen at that level.
    struct Point: Codable, Sendable, Equatable {
        let at: Date
        let price: Double
    }

    /// How many points a series keeps. At one entry per distinct price, 120 covers months of a gold board
    /// that moves a few times a day — and it bounds the stored blob, which shares UserDefaults with the
    /// watchlist and must not grow without limit.
    static let capacity = 120

    private(set) var points: [Point] = []

    /// Record `price` if it differs from the last one recorded.
    ///
    /// Equality and not a tolerance: these are published board prices, quoted in whole dong, so a repeat
    /// really is a repeat rather than float noise. The oldest point is dropped once the buffer is full,
    /// which makes this a ring in behaviour without being one in storage — an array of 120 encodes and
    /// compares far more simply than an index that has to survive a decode.
    mutating func record(_ price: Double, at date: Date) {
        guard price > 0 else { return }
        if let last = points.last, last.price == price { return }
        points.append(Point(at: date, price: price))
        if points.count > Self.capacity { points.removeFirst(points.count - Self.capacity) }
    }

    /// The closes a sparkline draws, oldest first — the same shape `QuoteSource.fetchHistory` returns, so
    /// the view cannot tell a recorded series from a fetched one.
    var closes: [Double] { points.map(\.price) }

    /// Whether this row's series has to be recorded because no feed will supply one.
    ///
    /// Named as a question about the FEED rather than a list of symbols, so a row that later gains an
    /// upstream series stops being logged by changing one answer rather than by being remembered here.
    static func isSelfRecorded(symbol: String, market: Market) -> Bool {
        market == .vietnam && DomesticIndex.isDomestic(symbol)
    }
}

/// Every self-recorded series, keyed by `WatchedSymbol.id`.
///
/// A type of its own rather than a bare dictionary because it is persisted, and because the pruning rule
/// belongs with it: a row removed from the watchlist should not leave its history behind to reappear
/// months later if the symbol is added back. That is a deliberate choice rather than an oversight — the
/// alternative, keeping it forever, means the app accumulates series for rows nobody watches.
struct PriceLogs: Codable, Sendable, Equatable {
    private(set) var logs: [String: PriceLog] = [:]

    subscript(id: String) -> PriceLog? { logs[id] }

    /// Record a batch of quotes, keeping only the rows that need recording.
    ///
    /// Returns whether anything changed, so the caller can skip a write on the overwhelming majority of
    /// polls — a rate sheet that has not moved since this morning writes nothing at all.
    @discardableResult
    mutating func record(_ entries: [WatchedSymbol], quotes: [String: Quote]) -> Bool {
        var changed = false
        for entry in entries where PriceLog.isSelfRecorded(symbol: entry.symbol, market: entry.market) {
            guard let quote = quotes[entry.id] else { continue }
            var log = logs[entry.id] ?? PriceLog()
            let before = log.points.count
            let lastBefore = log.points.last?.price
            // `asOf` and not the clock: the point is when the board published this price, so a gold board
            // read at four in the afternoon is recorded at the eleven o'clock it was set at.
            log.record(quote.price, at: quote.asOf)
            if log.points.count != before || log.points.last?.price != lastBefore {
                logs[entry.id] = log
                changed = true
            }
        }
        return changed
    }

    /// Drop the series for rows that are no longer watched.
    @discardableResult
    mutating func prune(keeping live: Set<String>) -> Bool {
        let kept = logs.filter { live.contains($0.key) }
        guard kept.count != logs.count else { return false }
        logs = kept
        return true
    }
}
