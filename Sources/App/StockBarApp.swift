// StockBarApp.swift — app entry point for StockBar, a menu bar stock/crypto ticker.
//
// Requires : macOS 13 Ventura or later + Xcode Command Line Tools (xcode-select --install).
//            Full Xcode is not needed — see build_app.sh.
//
// Build/run :  ./build_app.sh
//
// Data comes straight from two public JSON backends over URLSession — VPS for Vietnamese equities and
// indices, Binance for crypto (see VNQuoteSource / CryptoQuoteSource). No Python, no vendored
// framework, no API key.
//
// The menu-bar item is built with NSStatusItem + NSPopover rather than SwiftUI's MenuBarExtra, for two
// reasons. First, the label must be multi-coloured (green/red, plus purple and cyan for a VN
// ceiling/floor lock) and MenuBarExtra renders its label as a template — monochrome. Second,
// MenuBarExtra's `isPresented` desynchronises when its window is closed from the outside, which
// produces the familiar "first click does nothing" bug. Owning the popover directly avoids both.

import SwiftUI
import AppKit
import Combine

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let watchlist = Watchlist()
    private lazy var reader = QuoteReader(watchlist: watchlist)

    /// Sparkle. Created lazily so its background scheduler starts on the first access below (inside
    /// applicationDidFinishLaunching) rather than during property initialisation, and held for the
    /// app's lifetime — an SPUUpdater that is deallocated stops checking.
    private lazy var updater = Updater()

    private var statusItem: NSStatusItem!
    private var actionTarget: ClickTarget?
    private let popover = NSPopover()

    /// Last glyph cache key, so the status-item image is re-rendered only when what it displays
    /// actually changes rather than on every tick — the render does real text measurement and CG
    /// drawing, and at a 1 Hz refresh an unconditional rebuild is pure waste for a label that only
    /// changes once a minute.
    private var lastGlyphKey: String?

    private var outsideClickMonitor: Any?
    private var defaultsObserver: NSObjectProtocol?
    private var cancellables: Set<AnyCancellable> = []

    /// Cached preference, so the 1 Hz refreshLabel reads an in-memory Bool rather than querying
    /// UserDefaults on every tick. Absent key ⇒ shown, so a fresh install gets the informative default.
    private var showChangeInMenuBar = true

    /// A retained target for the status button's target/action that forwards to a Swift closure.
    private final class ClickTarget: NSObject {
        private let handler: () -> Void
        init(_ handler: @escaping () -> Void) { self.handler = handler }
        @objc func fire() { handler() }
    }

    /// Rebuilds the menu-bar glyph ~1 Hz. The quotes themselves only move once a minute, but this
    /// cadence is also what makes a light/dark switch, a stale-quote fade and a watchlist edit show up
    /// promptly; the cache key makes the ticks where nothing changed nearly free.
    private lazy var labelPoll = PollingTimer { [weak self] in
        MainActor.assumeIsolated { self?.refreshLabel() }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Menu-bar-only app: no Dock icon, no app menu (the .app bundle also sets LSUIElement).
        NSApp.setActivationPolicy(.accessory)

        let host = NSHostingController(
            rootView: TickerPopover(reader: reader,
                                    watchlist: watchlist,
                                    updater: updater,
                                    checkForUpdates: { [weak self] in
                                        // Close first: the popover is .applicationDefined, so it would
                                        // otherwise sit on top of the update window it just opened.
                                        self?.closePopover()
                                        self?.updater.checkForUpdates()
                                    },
                                    quitAction: { NSApp.terminate(nil) })
        )
        host.sizingOptions = [.preferredContentSize]
        // .applicationDefined, not .transient: the system never dismisses it behind our back, so the
        // open/close state stays truthful and a click on the item is always a single toggle.
        popover.behavior = .applicationDefined
        popover.animates = false
        popover.contentViewController = host

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let target = ClickTarget { [weak self] in self?.togglePopover() }
        actionTarget = target
        statusItem.button?.target = target
        statusItem.button?.action = #selector(ClickTarget.fire)

        // Redraw as soon as new quotes land instead of waiting for the next poll tick, so a manual
        // Refresh feels immediate.
        reader.$quotes
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.refreshLabel() }
            .store(in: &cancellables)
        watchlist.$symbols
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.refreshLabel() }
            .store(in: &cancellables)

        updateSettingsCache()
        defaultsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.updateSettingsCache()
                self?.refreshLabel()
            }
        }

        refreshLabel()
        labelPoll.schedule(every: 1)

        // A global monitor sees only clicks in OTHER apps / the desktop — never our own popover's
        // interior or our status button — which is exactly the "clicked away" case that should dismiss.
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) {
            [weak self] _ in
            MainActor.assumeIsolated { self?.closePopover() }
        }
    }

    private func togglePopover() {
        if popover.isShown {
            closePopover()
            return
        }
        guard let button = statusItem.button else { return }
        // An accessory app isn't the active app, so a freshly shown popover opens UNFOCUSED — its text
        // field and buttons wouldn't respond until you clicked into it. Activating BEFORE show, then
        // keying the window on the next run-loop turn (by which point activation has landed), is what
        // makes the first click work.
        if #available(macOS 14.0, *) { NSApp.activate() } else { NSApp.activate(ignoringOtherApps: true) }
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        DispatchQueue.main.async { [weak self] in
            self?.popover.contentViewController?.view.window?.makeKey()
        }
        reader.setPanelOpen(true)
    }

    private func closePopover() {
        guard popover.isShown else { return }
        popover.performClose(nil)
        reader.setPanelOpen(false)
    }

    /// Rebuild the status-item image from the pinned symbols, skipping the render when nothing that
    /// shows has changed.
    private func refreshLabel() {
        let pinned = watchlist.pinned
        let isDark = NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua

        var entries: [MenuBarEntry] = []
        // The appearance is folded into the key because the glyph bakes its own neutral text colour
        // (a coloured image can't be a template), so it would otherwise not re-tint on a theme switch.
        // The percentage toggle is folded in for the same reason: it changes what's drawn.
        var key = "\(isDark ? "d" : "l")\(showChangeInMenuBar ? "%" : "")"

        for entry in pinned {
            guard let q = reader.quotes[entry.id] else {
                key += "|\(entry.symbol):—"
                continue
            }
            let isIndex = isIndexSymbol(entry.symbol)
            let stale = reader.isStale(entry.id)
            // fmtPrice/fmtChangePercent — the SAME formatters the popover uses, so the menu bar and the
            // panel can never disagree about what an instrument costs.
            let price = fmtPrice(q.price, market: q.market, isIndex: isIndex)
            // Each pinned symbol's percentage costs ~45pt of menu bar. Users with a crowded menu bar
            // (or many pinned symbols) can trade it away for width; the popover always shows it.
            let change = showChangeInMenuBar ? q.changePercent.map { fmtChangePercent($0) } : nil
            let band = q.band

            entries.append(MenuBarEntry(label: entry.menuBarLabel,
                                        price: price,
                                        change: change,
                                        color: bandNSColor(band, market: q.market),
                                        stale: stale))
            key += "|\(entry.menuBarLabel):\(price):\(change ?? "-"):\(band):\(stale ? 1 : 0)"
        }

        guard key != lastGlyphKey else { return }
        lastGlyphKey = key
        statusItem.button?.image = tickerMenuBarImage(entries)
        statusItem.button?.setAccessibilityLabel(accessibilityLabel(entries))
    }

    private func updateSettingsCache() {
        showChangeInMenuBar = UserDefaults.standard.object(forKey: "showChangeInMenuBar") as? Bool ?? true
    }

    /// What VoiceOver reads for the item. Rebuilt only when the glyph is, so it stays in step with the
    /// image without allocating a string every tick.
    private func accessibilityLabel(_ entries: [MenuBarEntry]) -> String {
        guard !entries.isEmpty else { return "StockBar, no quotes yet" }
        return entries
            .map { "\($0.label) \($0.price)\($0.change.map { c in ", \(c)" } ?? "")" }
            .joined(separator: "; ")
    }
}

@main
struct StockBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // No visible scene — the UI is the NSStatusItem built in AppDelegate. Settings gives the App a
        // valid (empty, never-shown) scene body.
        Settings { EmptyView() }
    }
}
