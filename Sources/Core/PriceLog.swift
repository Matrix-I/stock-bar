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
// AND NEVER MORE THAN ONE POINT PER HALF HOUR, because that change filter turns out to be no filter at all
// for one of these three rows. SJC and USDVND are step functions and the filter collapses them beautifully;
// GOLDGAP is arithmetic over a world spot price that moves every minute, so it differs at EVERY poll and
// every poll was being written down. It filled the whole buffer in about two hours and rewrote the stored
// blob sixty times an hour to do it — a sparkline of one afternoon, in a file whose header promised months.
// The spacing floor costs the step functions nothing: a gold board revising twice inside thirty minutes is
// rare, and when it happens the later revision is the one that survives, because a change suppressed by the
// window is not discarded — the price still differs at the next poll past it, and is recorded then.
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

    /// How many points a series keeps. It bounds the stored blob, which shares UserDefaults with the
    /// watchlist and must not grow without limit. Against the two rules above it buys about two months of a
    /// gold board that moves a few times a day, and about five days of the gap, which moves continuously
    /// and is therefore held to the spacing floor rather than to its own rate of change.
    static let capacity = 240

    /// The shortest gap between two recorded points, on the observing clock. See the header: without it the
    /// derived row alone consumes the whole buffer in an afternoon.
    static let minimumInterval: TimeInterval = 30 * 60

    private(set) var points: [Point] = []

    /// When this series last took a point, measured by WHEN THE APP LOOKED rather than by when the price
    /// was published.
    ///
    /// Two clocks, deliberately, and for the derived row they are nowhere near each other: `GOLDGAP.asOf`
    /// is the oldest of its three inputs, which is PNJ's publication time — a stamp that stands still all
    /// afternoon while the gap itself moves with world gold. Spacing points by that would record one a day
    /// and call it a chart. Spacing them by when the app looked records what actually happened.
    ///
    /// Optional so a log stored before this field existed still decodes: the synthesised decoder reads an
    /// Optional with `decodeIfPresent`, which is the trap `WatchedSymbol` had to be rescued from by hand.
    private(set) var lastObserved: Date?

    /// Record `price`, stamped `date`, as seen at `now` — if it differs from the last point AND the
    /// spacing floor has passed.
    ///
    /// Equality and not a tolerance on the price: these are published board prices, quoted in whole dong,
    /// so a repeat really is a repeat rather than float noise. Note the order of the two tests — an
    /// unchanged price returns before the clock is consulted, so a quiet board does not spend its window
    /// on nothing and a move an hour later is recorded the moment it is seen.
    ///
    /// The oldest point is dropped once the buffer is full, which makes this a ring in behaviour without
    /// being one in storage — a flat array encodes and compares far more simply than an index that has to
    /// survive a decode.
    mutating func record(_ price: Double, at date: Date, observed now: Date) {
        guard price > 0 else { return }
        if let last = points.last, last.price == price { return }
        if let lastObserved, now.timeIntervalSince(lastObserved) < Self.minimumInterval { return }
        lastObserved = now
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
    mutating func record(_ entries: [WatchedSymbol], quotes: [String: Quote], now: Date) -> Bool {
        var changed = false
        for entry in entries where PriceLog.isSelfRecorded(symbol: entry.symbol, market: entry.market) {
            guard let quote = quotes[entry.id] else { continue }
            var log = logs[entry.id] ?? PriceLog()
            let before = log
            // A point is STAMPED with `asOf` and SPACED by `now`. The stamp is when the board published
            // this price, so a gold board read at four in the afternoon is recorded at the eleven o'clock
            // it was set at; the spacing is when this app looked, which is the only clock that advances for
            // every row. See `PriceLog.lastObserved` for why they cannot be the same date.
            log.record(quote.price, at: quote.asOf, observed: now)
            // Compared whole rather than by point count: `lastObserved` moves with a recorded point too,
            // and a change this misses is a change the disk never hears about.
            if log != before {
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
