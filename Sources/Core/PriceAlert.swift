// PriceAlert.swift — a threshold on a row, and the rule that decides when crossing it is news.
//
// The app already polls every minute and already keeps the last good quote for every row, so the fetching
// half of an alert was finished before this file existed. What was missing is the only hard part: deciding
// when a crossing is worth interrupting somebody for. Two failure modes bracket it, and both are worse than
// having no alerts at all.
//
// FIRING ON EVERY TICK. A price resting on its threshold crosses it back and forth all session. Firing each
// time turns a notification into noise, and a notification that is noise gets the app's permission revoked
// — permanently, and by a user who will not go looking for the setting again. So an alert fires ONCE and
// then disarms, and only rearms when the price has come back through the line by a clear margin.
//
// FIRING THE MOMENT IT IS SET. An alert typed while the price is already past the threshold has nothing to
// report: it would announce the number the user was looking at when they typed it. Such an alert starts
// disarmed and waits for a real crossing, which is why `init` needs the current price.
//
// What this file cannot fix, and what the UI has to say instead: an alert can only fire while the app is
// running and while the row's own venue is open, because a closed venue is not polled. "Tell me if gold
// drops overnight" works — spot gold trades overnight — while the same alert on a HOSE ticker cannot fire
// before nine in the morning. That is a property of a menu-bar app with no server behind it, not a bug, but
// it is invisible unless it is said out loud.

import Foundation

struct PriceAlert: Codable, Sendable, Hashable {

    enum Direction: String, Codable, Sendable, CaseIterable {
        case above
        case below
    }

    let direction: Direction
    let threshold: Double

    /// Whether this alert is waiting to fire. Persisted with the row, so quitting the app does not rearm
    /// every alert that has already had its say — a relaunch would otherwise repeat this morning's news.
    var isArmed: Bool

    /// How far back through the threshold the price must come before the alert is live again, as a
    /// fraction of the threshold. Half a percent: wide enough that ordinary noise around the line cannot
    /// rearm it, narrow enough that a genuine reversal does. A flat margin in price units cannot work here
    /// — the same app quotes a 26,410 dong rate and a 0.4 dollar token.
    static let rearmMargin = 0.005

    init(direction: Direction, threshold: Double, currentPrice: Double?) {
        self.direction = direction
        self.threshold = threshold
        // Armed unless the condition already holds — see the header.
        self.isArmed = !Self.holds(direction: direction, threshold: threshold, price: currentPrice)
    }

    /// Whether `price` satisfies this alert's condition right now. Says nothing about whether it should
    /// fire; that is `advanced(to:)`'s job, and the difference between the two is the whole point.
    static func holds(direction: Direction, threshold: Double, price: Double?) -> Bool {
        guard let price else { return false }
        switch direction {
        case .above: return price >= threshold
        case .below: return price <= threshold
        }
    }

    var holdsDescription: String {
        direction == .above ? "above" : "below"
    }

    /// This alert after seeing `price`, and whether that reading is worth announcing.
    ///
    /// Returned as a new value rather than mutated in place so the caller can persist the whole watchlist
    /// once, and so this stays a pure function the tests can walk a price series through.
    func advanced(to price: Double) -> (alert: PriceAlert, fires: Bool) {
        let satisfied = Self.holds(direction: direction, threshold: threshold, price: price)

        if isArmed {
            guard satisfied else { return (self, false) }
            var fired = self
            fired.isArmed = false
            return (fired, true)
        }

        // Disarmed: rearm only once the price is clear of the line by the margin, so a price sitting on
        // the threshold cannot pump the alert.
        let slack = abs(threshold) * Self.rearmMargin
        let rearmed: Bool
        switch direction {
        case .above: rearmed = price < threshold - slack
        case .below: rearmed = price > threshold + slack
        }
        guard rearmed else { return (self, false) }
        var live = self
        live.isArmed = true
        return (live, false)
    }
}

/// Walks the watchlist against the latest quotes and reports what crossed.
///
/// In Core, and pure, because this is the app's one piece of logic whose output is an interruption. A bug
/// here does not draw a wrong number on a panel nobody is looking at — it wakes somebody up. It is also
/// the kind of logic that cannot be checked by looking: the difference between "fires once" and "fires
/// every minute" takes an hour of real time to observe and one test to state.
enum AlertEngine {

    /// One alert that just went off.
    struct Firing: Sendable, Equatable, Identifiable {
        /// `WatchedSymbol.id`, so a notification can be de-duplicated per row by the system.
        let id: String
        let symbol: String
        let market: Market
        let isIndex: Bool
        let alert: PriceAlert
        let price: Double

        /// What the notification says. Built here rather than in the notifier so it goes through the same
        /// `PriceFormat` as the panel — an alert quoting a price the panel spells differently is the same
        /// class of bug that formatter exists to prevent.
        var title: String { symbol.uppercased() }

        var body: String {
            let now = PriceFormat.price(price, market: market, isIndex: isIndex)
            let line = PriceFormat.price(alert.threshold, market: market, isIndex: isIndex)
            return "\(now) — \(alert.holdsDescription) \(line)"
        }
    }

    /// Evaluate every alert on every row.
    ///
    /// Returns the watchlist as it should now be stored alongside the firings, because arming state changes
    /// on rows that did NOT fire as well: a price falling back through a line rearms an alert without
    /// announcing anything, and losing that write means the alert never fires again.
    ///
    /// A row with no quote is skipped rather than treated as zero, which would fire every `below` alert in
    /// the list the first time a fetch failed.
    static func evaluate(_ entries: [WatchedSymbol],
                         quotes: [String: Quote]) -> (fired: [Firing], updated: [WatchedSymbol]) {
        var fired: [Firing] = []
        var updated = entries

        for (i, entry) in entries.enumerated() where !entry.alerts.isEmpty {
            guard let quote = quotes[entry.id] else { continue }
            var alerts = entry.alerts
            for (j, alert) in alerts.enumerated() {
                let (next, fires) = alert.advanced(to: quote.price)
                alerts[j] = next
                if fires {
                    fired.append(Firing(id: entry.id, symbol: entry.symbol, market: entry.market,
                                        isIndex: entry.isIndex, alert: alert, price: quote.price))
                }
            }
            updated[i].alerts = alerts
        }
        return (fired, updated)
    }
}
