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

    /// Last good quote per `WatchedSymbol.id`, exactly as the feed reported it. Never pruned on failure —
    /// see the note above. Private, because a fetched quote is not what anything should draw: read `quotes`.
    @Published private var lastGood: [String: Quote] = [:]

    /// The quotes to draw, which is what was fetched read at the current moment.
    ///
    /// Computed rather than stored because the correction is a function of the clock, not of the fetch. Once
    /// HOSE closes nothing is fetched again until it opens — `shouldFetch` sees no reason to — so a quote
    /// baked at 15:00 is the same object the menu bar is still drawing at 00:01, and rebasing it on the way
    /// in would have nothing to trigger it at midnight. Doing it on the way out means the flip costs nothing
    /// and happens on the tick: the menu bar rebuilds at 1 Hz, and the panel re-renders whenever `lastGood`
    /// is reassigned, which `apply` does on every poll whether or not anything was fetched.
    ///
    /// Applying it here rather than at the three call sites is deliberate. The menu bar, the row and the
    /// detail card would otherwise each have to remember to ask, and the one that forgot would disagree with
    /// the other two about the same instrument — which is the class of bug `PriceFormat` exists to prevent.
    var quotes: [String: Quote] {
        let now = Date()
        return lastGood.mapValues { $0.rebasedForPendingSession(at: now) }
    }

    /// Fires when a fetch has been merged. Subscribed to by the menu bar so a manual Refresh redraws at
    /// once instead of at its next 1 Hz tick. It publishes the fetched dictionary rather than the drawn one
    /// because it is a signal, not a value — a subscriber that wants the numbers reads `quotes`.
    var quotesDidChange: Published<[String: Quote]>.Publisher { $lastGood }
    /// Recent closes per `WatchedSymbol.id`, as fetched from a feed. Only fetched while the popover is
    /// open, since nothing else draws them. Private: read `history`, which also knows about the rows this
    /// app records for itself.
    @Published private var fetchedHistory: [String: [Double]] = [:]

    /// What the sparklines draw: a feed's bars where a feed has them, and this app's own recorded series
    /// where none exists — SJC, USDVND and the gold gap. See Core/PriceLog.swift.
    ///
    /// Merged here rather than at the three call sites, so a row cannot draw a fetched chart in one place
    /// and a recorded one in another. A fetched series always wins: a feed that starts publishing bars for
    /// a row this app was logging should take over immediately, and never be second-guessed by a shorter
    /// home-made one.
    var history: [String: [Double]] {
        var merged = fetchedHistory
        for (id, closes) in priceLogs.recordedSeries where merged[id]?.isEmpty != false {
            merged[id] = closes
        }
        return merged
    }
    /// Trailing per-share figures per `WatchedSymbol.id`, behind the P/E and P/B in the detail card. Only
    /// Vietnamese equities have them; everything else stays absent, which the card simply renders fewer
    /// rows for.
    @Published private(set) var fundamentals: [String: Fundamentals] = [:]
    /// Advancers and decliners per FLOOR — "HOSE", "HNX" — behind the breadth line on an index card.
    /// Keyed by floor rather than by row id because two index rows can summarise the same floor, and
    /// counting it twice would be two 400 KB requests for one number.
    @Published private(set) var breadth: [String: Breadth] = [:]
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
    private let world = WorldQuoteSource()
    private let fundamentalsFeed = FundamentalsSource()
    private let breadthFeed = BreadthSource()
    /// The series this app records for the rows no feed gives one for — see Core/PriceLog.swift.
    private let priceLogs: PriceLogStore
    private let notifier = AlertNotifier()

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

    /// `priceLogs` is injectable so `Tools/uisnap.sh` can hand in a store backed by its own defaults
    /// domain — without that, a snapshot run would append to the real app's recorded series.
    /// Constructed in the body rather than as a default argument: a default is evaluated outside the
    /// initialiser's actor isolation, and `PriceLogStore` is main-actor bound.
    init(watchlist: Watchlist, priceLogs: PriceLogStore? = nil) {
        self.watchlist = watchlist
        self.priceLogs = priceLogs ?? PriceLogStore()

        // Refresh the moment the lid opens. A Timer does not fire while the machine is asleep and does
        // not "catch up" on wake — it simply resumes on its original schedule, so without this the menu
        // bar can show a price from before a multi-hour sleep for up to a full interval.
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }

        // Editing the watchlist should show the new row immediately, not at the next tick.
        //
        // The list has to be taken from the publisher and passed in. `@Published` publishes from `willSet`,
        // so inside this closure `watchlist.symbols` is still the list from BEFORE the edit — a refresh
        // that read the property would build its plan without the symbol just added and fetch nothing for
        // it, leaving the new row on a dash until the next tick or a manual Refresh. It looked intermittent
        // because it wasn't always reached: an add during an in-flight fetch is deferred by `refreshQueued`
        // and runs later, by which point the property has caught up and the row fills in correctly.
        //
        // Only when the SET of rows changes. Pinning, reordering and — since alerts — this class writing
        // arming state back on every poll all republish the list, and refetching for any of them would be
        // waste at best: an alert rearming would trigger a fetch, whose result would rearm another, and the
        // 60-second cadence would quietly become "as fast as the network allows".
        watchlistChanges = watchlist.$symbols
            .dropFirst()
            .removeDuplicates { Set($0.map(\.id)) == Set($1.map(\.id)) }
            .sink { [weak self] edited in self?.refresh(using: edited) }

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
    ///
    /// Asked per SYMBOL, not per market, which only matters for the world instruments: `.world` counts as
    /// open whenever any of its venues is trading, and a Dow row would otherwise grey out for the whole
    /// Tokyo session.
    ///
    /// The venue's own data delay is added to the allowance, and that is not a detail. ICE holds free data
    /// back by ten minutes, so a dollar-index quote is ALWAYS about 600 seconds old while the venue trades.
    /// Against the bare interval the row rendered permanently dimmed — a working feed reporting itself
    /// broken, on a row most likely to be looked at overnight.
    func isStale(_ id: String) -> Bool {
        guard let q = lastGood[id] else { return false }
        guard MarketHours.isOpen(q.market, symbol: q.symbol) else { return false }
        let allowance = Self.activeInterval * 1.5
            + WorldIndex.feedDelay(for: q.symbol)
            + DomesticIndex.feedDelay(for: q.symbol)
        return Date().timeIntervalSince(q.asOf) > allowance
    }

    /// Every position added into one VND figure, or nil when nothing convertible is held — see Portfolio.
    ///
    /// Computed on read rather than stored, for the same reason `quotes` is: it is a function of the
    /// watchlist and the cache, both of which already publish, so a stored copy would be a third thing to
    /// keep in step with them. Reads `quotes` and not `lastGood`, so the total is built from the same
    /// numbers the rows above it are drawing.
    var portfolio: Portfolio? {
        Portfolio.total(for: watchlist.symbols, quotes: quotes)
    }

    /// Whether any row feeding the total is stale, so the summary dims with the rows it sums rather than
    /// standing at full contrast over a board that has visibly stopped.
    var isPortfolioStale: Bool {
        watchlist.symbols.contains { $0.holding?.isEmpty == false && isStale($0.id) }
            || isStale("vietnam:USDVND")
    }

    /// Every currently stale id, for the menu-bar label. Passed as a set rather than having MenuBarLabel
    /// call `isStale` itself: that keeps the wall clock out of the pure layer, so a label can be compared
    /// for equality and asserted on in a test.
    var staleIDs: Set<String> {
        Set(lastGood.keys.filter { isStale($0) })
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
    /// Deliberately does not write to `lastGood`: a symbol merely being considered has no row yet, and
    /// caching a price for it would flash a value into a list it may never join.
    func validate(_ symbol: String, market: Market) async -> SymbolCheck {
        let wanted = Ticker.canonical(symbol)
        guard !wanted.isEmpty else { return .unknown }
        // A computed row has no venue to ask, and asking anyway would route it to a feed that has never
        // heard of it and get back a "does not exist" for a row this app defines itself.
        guard !DerivedQuote.isDerived(wanted) else { return .ok }
        let source = self.source(for: market)
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

    /// Set or clear one direction's alert on a row.
    ///
    /// Here rather than on `Watchlist` because setting an alert needs two things that store does not have:
    /// the current price, which decides whether the alert starts armed, and the notifier, which has to ask
    /// for permission at exactly this moment — the one point where the user has demonstrably asked to be
    /// interrupted. `quotes` and not `lastGood`, so the comparison is against the number on screen.
    func setAlert(_ entry: WatchedSymbol, direction: PriceAlert.Direction, threshold: Double?) {
        watchlist.setAlert(entry, direction: direction, threshold: threshold,
                           currentPrice: quotes[entry.id]?.price)
        if threshold != nil { notifier.requestAuthorizationIfNeeded() }
    }

    func refresh() {
        refresh(using: watchlist.symbols)
    }

    /// Fetch for exactly `symbols`.
    ///
    /// Separate from `refresh()` for one caller — the watchlist subscription, which is handed the edited
    /// list because the property it would otherwise read has not been updated yet. Kept as its own method
    /// rather than a defaulted parameter because `refresh` is passed around as a plain `() -> Void` (the
    /// panel's Refresh button), and a defaulted parameter cannot be referenced that way.
    private func refresh(using symbols: [WatchedSymbol]) {
        guard !inFlight else {
            refreshQueued = true
            return
        }
        inFlight = true
        isFetching = true

        let wantHistory = panelOpen
        // Which venues are worth calling this tick, and what to ask each for. Built here, on the main actor,
        // rather than inside the Task: `shouldFetch` reads `lastGood`, which is main-actor state, and
        // hoisting it means the Task captures a plain list instead of reaching back into self mid-flight.
        // One entry per market rather than three hand-written branches, so a fourth venue is a case in
        // `source(for:)` and nothing here.
        //
        // Planned against `tracked` rather than `symbols`: a derived row is computed from other rows, and
        // watching only the gap has to fetch the three it is made of. Those extra entries are cached but
        // never drawn — the panel iterates the watchlist, which does not contain them.
        let tracked = DerivedQuote.tracked(symbols)
        let plan: [(market: Market, source: any QuoteSource, symbols: [String])] =
            Market.allCases.compactMap { market in
                let entries = tracked.filter {
                    $0.market == market && !DerivedQuote.isDerived($0.symbol) && shouldFetch($0)
                }
                guard !entries.isEmpty else { return nil }
                return (market, source(for: market), entries.map(\.symbol))
            }

        Task { [weak self] in
            guard let self else { return }
            var failures: [String] = []
            var fetched: [Quote] = []

            for step in plan {
                do {
                    fetched += try await step.source.fetchQuotes(for: step.symbols)
                } catch {
                    failures.append("\(step.market.shortLabel): \(error.localizedDescription)")
                }
            }

            self.apply(fetched, symbols: tracked, failures: failures)

            if wantHistory {
                await self.refreshHistory(for: symbols)
                await self.refreshFundamentals(for: symbols)
                await self.refreshBreadth(for: symbols)
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

    /// The venue implementation behind a market. The one place the mapping lives, so `refresh`, `validate`
    /// and the sparkline fetch cannot disagree about which backend serves a row.
    private func source(for market: Market) -> any QuoteSource {
        switch market {
        case .vietnam: return vn
        case .crypto:  return crypto
        case .world:   return world
        }
    }

    /// Whether one row is worth fetching this tick. Only ask for a symbol whose own venue is trading — but
    /// always ask for one we have no quote for at all, so a first launch outside session hours still fills
    /// the rows with the last close instead of showing dashes until Monday.
    ///
    /// Per ROW and not per market, which only shows on `.world`. It is a bucket of venues, and two of them
    /// — spot gold, and ICE for the dollar index — trade overnight, so the bucket now counts as open at
    /// every hour of a weekday. Asked per market, adding a gold row would therefore have refetched the Dow,
    /// the Nasdaq and the Nikkei every single minute all night, for numbers that cannot move until their own
    /// exchange opens.
    private func shouldFetch(_ entry: WatchedSymbol) -> Bool {
        MarketHours.isOpen(entry.market, symbol: entry.symbol) || lastGood[entry.id] == nil
    }

    /// Merge a batch of fetched quotes into `lastGood`, keyed back to the watchlist entry they belong to.
    ///
    /// The join is by (market, uppercased symbol) rather than by array position: the board endpoint
    /// returns rows in its own order and omits tickers it doesn't recognise, so positional matching
    /// would silently attach VCB's price to FPT's row the first time someone watches a delisted symbol.
    private func apply(_ fetched: [Quote], symbols: [WatchedSymbol], failures: [String]) {
        var byKey: [String: Quote] = [:]
        for q in fetched { byKey["\(q.market.rawValue):\(q.symbol.uppercased())"] = q }

        for entry in symbols {
            if let q = byKey[entry.id] { lastGood[entry.id] = q }
        }
        // Record the rows whose series this app has to keep for itself, before the derived values are
        // computed — SJC and USDVND are two of them, and the third is the gap they produce, which has to
        // be recorded from the merged result a few lines below rather than from anything fetched.
        priceLogs.record(symbols, quotes: lastGood)

        // The computed rows, after the fetched ones and from the merged result rather than from this batch:
        // the gap's three inputs are on two different clocks, so on most ticks at least one of them was not
        // refetched and only `lastGood` has all three.
        for (id, q) in DerivedQuote.values(for: symbols, from: lastGood) { lastGood[id] = q }
        // And again for the derived rows, which only exist after the line above. The recorder keeps a
        // point only when the price differs from the last one, so calling it twice costs nothing.
        priceLogs.record(symbols, quotes: lastGood)

        // Drop quotes for symbols no longer watched, so a removed row doesn't linger in the menu bar. The
        // set is the tracked list, not the visible one, so a derived row's inputs survive the prune that
        // runs the moment after they are fetched.
        let live = Set(symbols.map(\.id))
        lastGood = lastGood.filter { live.contains($0.key) }
        fetchedHistory = fetchedHistory.filter { live.contains($0.key) }
        fundamentals = fundamentals.filter { live.contains($0.key) }
        priceLogs.prune(keeping: live)

        if failures.isEmpty {
            lastError = nil
            if !fetched.isEmpty { lastSuccessAt = Date() }
        } else {
            lastError = failures.joined(separator: " · ")
        }

        evaluateAlerts()
    }

    /// Check every threshold against what was just merged, post whatever crossed, and store the new arming
    /// state.
    ///
    /// Over `watchlist.symbols` and not the tracked list: an alert belongs to a row the user put there, and
    /// a row pulled in only to feed a derived value is not one they asked to hear about. It reads `quotes`
    /// rather than `lastGood` so a threshold is compared against the number the panel is drawing — after
    /// the midnight rebase, not before it.
    private func evaluateAlerts() {
        let entries = watchlist.symbols
        guard entries.contains(where: { !$0.alerts.isEmpty }) else { return }
        let (fired, updated) = AlertEngine.evaluate(entries, quotes: quotes)
        watchlist.applyAlertStates(updated)
        for firing in fired { notifier.post(firing) }
    }

    /// Run one lookup per item concurrently and keep the answers that arrived, keyed by whatever the
    /// lookup names them.
    ///
    /// The three panel-only enrichments below were the same twenty lines three times over. Extracted
    /// because the interesting part is a policy rather than a mechanism, and a policy stated three times is
    /// one that ends up meaning three things: EVERY FAILURE HERE IS SWALLOWED. A missing sparkline, ratio
    /// or breadth line simply draws less, and none of them is worth a message under a panel whose prices
    /// arrived perfectly well. That is the opposite of the rule in `fetchEachSymbol`, which is about
    /// quotes — a row with no price is a row that cannot do its job, while a row with no chart is a row.
    private func gather<Item: Sendable, Value: Sendable>(
        _ items: [Item],
        _ lookup: @escaping @Sendable (Item) async -> (String, Value)?
    ) async -> [String: Value] {
        await withTaskGroup(of: (String, Value)?.self) { group in
            for item in items { group.addTask { await lookup(item) } }
            var out: [String: Value] = [:]
            for await result in group { if let result { out[result.0] = result.1 } }
            return out
        }
    }

    /// Fetch sparkline history for every watched symbol, concurrently.
    private func refreshHistory(for symbols: [WatchedSymbol]) async {
        // Each row's source is resolved up front so the task group captures values rather than self.
        let work = symbols.map { (entry: $0, source: source(for: $0.market)) }
        let fetched = await gather(work) { item -> (String, [Double])? in
            guard let closes = try? await item.source.fetchHistory(for: item.entry.symbol),
                  !closes.isEmpty else { return nil }
            return (item.entry.id, closes)
        }
        fetchedHistory.merge(fetched) { _, new in new }
    }

    /// Fetch trailing per-share figures for the Vietnamese equities, concurrently.
    ///
    /// Called on every panel refresh even though the figures change once a quarter. FundamentalsSource
    /// caches per ICT day, so this costs one request per equity per day and nothing after that — and going
    /// through it each time is what makes the cache expire by itself when the day rolls over.
    private func refreshFundamentals(for symbols: [WatchedSymbol]) async {
        let feed = fundamentalsFeed
        let wanted = symbols.filter(\.hasPerShareFundamentals)
        guard !wanted.isEmpty else { return }

        let fetched = await gather(wanted) { entry -> (String, Fundamentals)? in
            guard let value = try? await feed.fetch(for: entry.symbol), !value.isEmpty else { return nil }
            return (entry.id, value)
        }
        fundamentals.merge(fetched) { _, new in new }
    }

    /// Count advancers and decliners for every floor an index row on the list summarises.
    ///
    /// Panel-only, like the sparklines and for a stronger version of the same reason: this is the heaviest
    /// request the app makes — a whole floor's board, some 400 KB — and it backs one line on one card. The
    /// source caches for a minute on top of that, so opening and closing the panel repeatedly costs one
    /// fetch rather than one per visit.
    ///
    /// By floor and not by row, so VNINDEX and a second HOSE index on the same list share one count.
    private func refreshBreadth(for symbols: [WatchedSymbol]) async {
        let floors = Set(symbols.compactMap { Breadth.floor(for: $0.symbol) })
        guard !floors.isEmpty else { return }
        let feed = breadthFeed

        // Keyed by floor rather than by row id, which is the one place `gather`'s key is not a symbol id.
        let fetched = await gather(Array(floors)) { floor -> (String, Breadth)? in
            guard let value = try? await feed.breadth(for: floor) else { return nil }
            return (floor, value)
        }
        breadth.merge(fetched) { _, new in new }
    }

    /// Pick the polling interval from whether anything being watched is currently trading. Idempotent —
    /// PollingTimer no-ops when the interval is unchanged — so calling it after every refresh is cheap
    /// and means the cadence tightens by itself the minute HOSE opens.
    ///
    /// Asked per symbol, matching `shouldFetch`, so the cadence can never be faster than the reason for it:
    /// asked per market, a watchlist holding only the Dow would run at the 60-second interval every night —
    /// `.world` counts as open because spot gold is trading — and every one of those ticks would build an
    /// empty plan and fetch nothing at all.
    private func applyCadence() {
        // Over the tracked list, matching the plan: a watchlist holding only the gold gap has nothing of its
        // own to fetch, and reading the visible rows alone would drop to the idle cadence while the three
        // rows it is computed from were still moving.
        let anyOpen = DerivedQuote.tracked(watchlist.symbols)
            .contains { MarketHours.isOpen($0.market, symbol: $0.symbol) }
        poll.schedule(every: anyOpen ? Self.activeInterval : Self.idleInterval)
    }
}
