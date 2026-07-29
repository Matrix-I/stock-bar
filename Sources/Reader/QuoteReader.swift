// QuoteReader.swift — the single ObservableObject the menu bar and the popover both read. It owns the
// refresh cadence, fans each tick out to the per-market sources, and holds the last good quote for
// every watched symbol.
//
// Two decisions shape the whole class:
//
// 1. A failed fetch NEVER clears a quote. Quotes are kept in a dictionary that is only ever written
//    to, so a dropped Wi-Fi connection leaves yesterday's close on screen (visibly ageing via
//    `asOf`) instead of blanking the menu bar. An empty menu bar reads as "the app crashed"; a
//    greyed one reads as "the data is old", which is the truth.
//
// 2. Cadence follows the markets, not the clock. Polling a closed exchange all night is pure waste —
//    HOSE trades ~5 hours a weekday, so gating on session hours removes about 85% of requests and
//    stops the machine waking every minute to fetch a number that cannot move. Crypto never closes,
//    so a watchlist containing any crypto keeps the fast cadence.

import Foundation
import Combine
import AppKit

@MainActor
final class QuoteReader: ObservableObject {

    /// Last good quote per `WatchedSymbol.id`. Never pruned on failure — see the note above.
    @Published private(set) var quotes: [String: Quote] = [:]
    /// Recent closes per `WatchedSymbol.id` for the popover sparklines. Only fetched while the popover
    /// is open, since nothing else draws them.
    @Published private(set) var history: [String: [Double]] = [:]
    /// Human-readable description of the most recent failure, cleared by the next success. Shown as a
    /// footer in the popover rather than an alert — a transient fetch failure is not worth a modal.
    @Published private(set) var lastError: String?
    @Published private(set) var lastSuccessAt: Date?
    @Published private(set) var isFetching = false

    /// Interval used while any watched market is trading.
    private static let activeInterval: TimeInterval = 60
    /// Interval used when every watched market is closed — long enough to be nearly free, short enough
    /// that the board is already current a few minutes into the next session.
    private static let idleInterval: TimeInterval = 600

    private let watchlist: Watchlist
    private let vn = VNQuoteSource()
    private let crypto = CryptoQuoteSource()

    private lazy var poll = PollingTimer { [weak self] in self?.refresh() }
    private var panelOpen = false
    /// Guards against overlapping refreshes: a second fetch is never started while one is in flight,
    /// because piling requests on a struggling link makes it worse.
    private var inFlight = false
    /// Set when a refresh arrives while one is in flight, and honoured once it finishes. Without this,
    /// opening the popover (which refreshes, including the slower sparkline fetch) made the Refresh
    /// button do *nothing at all* for the next few seconds — the request was dropped silently, which
    /// reads as a dead button. At most one is remembered, so a burst of clicks collapses into one
    /// follow-up fetch rather than a queue.
    private var refreshQueued = false
    private var wakeObserver: NSObjectProtocol?
    private var watchlistChanges: AnyCancellable?

    init(watchlist: Watchlist) {
        self.watchlist = watchlist

        // Refresh the moment the lid opens. A Timer does not fire while the machine is asleep and does
        // not "catch up" on wake — it simply resumes on its original schedule, so without this the menu
        // bar can show a price from before a multi-hour sleep for up to a full interval.
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }

        // Editing the watchlist should show the new row immediately, not at the next tick.
        watchlistChanges = watchlist.$symbols
            .dropFirst()
            .sink { [weak self] _ in self?.refresh() }

        refresh()
        applyCadence()
    }

    deinit {
        if let wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver)
        }
    }

    /// Tell the reader whether the popover is on screen. Sparklines are only fetched while it is, and
    /// opening it triggers an immediate refresh so the panel never opens onto a minute-old board.
    func setPanelOpen(_ open: Bool) {
        guard panelOpen != open else { return }
        panelOpen = open
        if open { refresh() }
    }

    /// Whether `id`'s quote is old enough to render as stale. One and a half intervals while the market
    /// is trading: long enough that an ordinary tick never trips it, short enough to notice a feed that
    /// has stopped.
    ///
    /// A CLOSED market is never stale. Its last close is the most current price that exists, so ageing it
    /// out greys the whole board every evening and makes a perfectly healthy feed look broken. It also
    /// removed a real inconsistency: index quotes carry the timestamp of their last 1-minute bar (15:00),
    /// while the equity board reports the fetch time, so after the close the indices greyed out and the
    /// equities beside them did not — same data, two different appearances.
    func isStale(_ id: String) -> Bool {
        guard let q = quotes[id] else { return false }
        guard MarketHours.isOpen(q.market) else { return false }
        return Date().timeIntervalSince(q.asOf) > Self.activeInterval * 1.5
    }

    /// The verdict on a symbol someone is trying to add. Three cases rather than a Bool because "the
    /// venue has never heard of this" and "the check itself failed" call for different words on screen —
    /// telling someone their ticker doesn't exist when the real problem was the network would send them
    /// looking for a typo that isn't there.
    enum SymbolCheck: Sendable, Equatable {
        /// The venue knows the symbol and quoted it.
        case ok
        /// The venue answered and does not list it: a typo, or a symbol belonging to the other market.
        case unknown
        /// The check could not be completed. Carries the reason, for the message.
        case unreachable(String)
    }

    /// Ask the venue whether `symbol` exists, before it is allowed into the watchlist.
    ///
    /// Worth the round trip because nothing downstream can tell a typo from a dead feed: an unrecognised
    /// ticker is simply *absent* from the board response, so it joins the list and shows a dash forever,
    /// looking exactly like a network problem. Checking once at the point of entry is the only place the
    /// difference is still knowable.
    ///
    /// Deliberately does not write to `quotes`: a symbol merely being considered has no row yet, and
    /// caching a price for it would flash a value into a list it may never join.
    func validate(_ symbol: String, market: Market) async -> SymbolCheck {
        let wanted = symbol.trimmingCharacters(in: .whitespaces).uppercased()
        guard !wanted.isEmpty else { return .unknown }
        let source: any QuoteSource = market == .vietnam ? vn : crypto
        do {
            let quoted = try await source.fetchQuotes(for: [wanted])
            return quoted.contains { $0.symbol.uppercased() == wanted } ? .ok : .unknown
        } catch QuoteError.badStatus(400) {
            // Binance rejects an unknown pair with 400 ("Invalid symbol") instead of returning an empty
            // result, so this particular status is a verdict on the symbol, not a transport failure. The
            // VN board takes the other route and just omits the row, which the check above catches.
            return .unknown
        } catch {
            return .unreachable(error.localizedDescription)
        }
    }

    func refresh() {
        guard !inFlight else {
            refreshQueued = true
            return
        }
        inFlight = true
        isFetching = true

        let symbols = watchlist.symbols
        let wantHistory = panelOpen
        let vnSymbols = symbols.filter { $0.market == .vietnam }
        let cryptoSymbols = symbols.filter { $0.market == .crypto }
        // Decided here, on the main actor, rather than inside the Task: it reads `quotes`, which is
        // main-actor state, and hoisting it also means the Task captures two plain Bools instead of
        // reaching back into self mid-flight.
        let fetchVN = shouldFetch(.vietnam, vnSymbols)
        let fetchCrypto = shouldFetch(.crypto, cryptoSymbols)

        Task { [weak self] in
            guard let self else { return }
            var failures: [String] = []
            var fetched: [Quote] = []

            if fetchVN {
                do {
                    fetched += try await self.vn.fetchQuotes(for: vnSymbols.map(\.symbol))
                } catch {
                    failures.append("VN: \(error.localizedDescription)")
                }
            }
            if fetchCrypto {
                do {
                    fetched += try await self.crypto.fetchQuotes(for: cryptoSymbols.map(\.symbol))
                } catch {
                    failures.append("Crypto: \(error.localizedDescription)")
                }
            }

            self.apply(fetched, symbols: symbols, failures: failures)

            if wantHistory {
                await self.refreshHistory(for: symbols)
            }

            self.inFlight = false
            self.isFetching = false
            self.applyCadence()

            // Honour a request that arrived mid-flight. Cleared before recursing, so this can only run
            // one extra fetch — it cannot become a loop even if clicks keep landing during that fetch
            // (they just set the flag again for one more round).
            if self.refreshQueued {
                self.refreshQueued = false
                self.refresh()
            }
        }
    }

    /// Whether a market is worth calling this tick. Only poll one that is actually trading — but always
    /// poll a market holding a symbol we have no quote for at all, so a first launch outside session
    /// hours still fills the rows with the last close instead of showing dashes until Monday.
    private func shouldFetch(_ market: Market, _ entries: [WatchedSymbol]) -> Bool {
        guard !entries.isEmpty else { return false }
        if MarketHours.isOpen(market) { return true }
        return entries.contains { quotes[$0.id] == nil }
    }

    /// Merge a batch of fetched quotes into `quotes`, keyed back to the watchlist entry they belong to.
    ///
    /// The join is by (market, uppercased symbol) rather than by array position: the board endpoint
    /// returns rows in its own order and omits tickers it doesn't recognise, so positional matching
    /// would silently attach VCB's price to FPT's row the first time someone watches a delisted symbol.
    private func apply(_ fetched: [Quote], symbols: [WatchedSymbol], failures: [String]) {
        var byKey: [String: Quote] = [:]
        for q in fetched { byKey["\(q.market.rawValue):\(q.symbol.uppercased())"] = q }

        for entry in symbols {
            if let q = byKey[entry.id] { quotes[entry.id] = q }
        }
        // Drop quotes for symbols no longer watched, so a removed row doesn't linger in the menu bar.
        let live = Set(symbols.map(\.id))
        quotes = quotes.filter { live.contains($0.key) }
        history = history.filter { live.contains($0.key) }

        if failures.isEmpty {
            lastError = nil
            if !fetched.isEmpty { lastSuccessAt = Date() }
        } else {
            lastError = failures.joined(separator: " · ")
        }
    }

    /// Fetch sparkline history for every watched symbol, concurrently. Errors are swallowed: a missing
    /// sparkline just draws nothing, and it is not worth surfacing next to a price that arrived fine.
    private func refreshHistory(for symbols: [WatchedSymbol]) async {
        let vnSource = vn
        let cryptoSource = crypto
        let results = await withTaskGroup(of: (String, [Double])?.self) { group in
            for entry in symbols {
                group.addTask {
                    do {
                        let closes = entry.market == .vietnam
                            ? try await vnSource.fetchHistory(for: entry.symbol)
                            : try await cryptoSource.fetchHistory(for: entry.symbol)
                        return closes.isEmpty ? nil : (entry.id, closes)
                    } catch {
                        return nil
                    }
                }
            }
            var out: [(String, [Double])] = []
            for await r in group { if let r { out.append(r) } }
            return out
        }
        for (id, closes) in results { history[id] = closes }
    }

    /// Pick the polling interval from whether anything being watched is currently trading. Idempotent —
    /// PollingTimer no-ops when the interval is unchanged — so calling it after every refresh is cheap
    /// and means the cadence tightens by itself the minute HOSE opens.
    private func applyCadence() {
        let anyOpen = watchlist.activeMarkets.contains { MarketHours.isOpen($0) }
        poll.schedule(every: anyOpen ? Self.activeInterval : Self.idleInterval)
    }
}
