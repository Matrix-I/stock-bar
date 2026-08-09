// uisnap.swift — renders the real TickerPopover to a PNG.
//
// Not part of the app. It exists because the popover is otherwise unverifiable from a terminal: this
// machine has no Screen Recording permission, so `screencapture` of the actual panel fails with "could
// not create image from display". Without this, checking a layout change means asking the user to take
// a screenshot — and a claim like "the version now shows in the header" would be unverified.
//
// It hosts the same TickerPopover the app shows, in a real NSWindow so SwiftUI lays out normally, then
// caches the view's display into a bitmap.
//
// Run: ./Tools/uisnap.sh /tmp/panel.png [dark|light]
//
// One honest limitation: Bundle.main here is this executable, not StockBar.app, so AppInfo.version
// falls back to "dev" instead of the bundle's real version. The PNG proves the version's *position and
// styling*; the value itself is verified separately against Info.plist.

import SwiftUI
import AppKit

@main
struct UISnap {
    @MainActor
    static func main() {
        let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "/tmp/panel.png"
        let theme = CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : "dark"
        let wantsDark = theme != "light"

        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        // Force the appearance rather than inheriting the machine's: a panel that only renders in one
        // theme is exactly the kind of bug this tool is for. "system" opts out, because forcing an
        // NSAppearance is itself worth ruling out when a control renders with the wrong colours.
        if theme != "system" {
            app.appearance = NSAppearance(named: wantsDark ? .darkAqua : .aqua)
        }

        let watchlist = Watchlist()
        // Always reset, unconditionally: Watchlist persists to UserDefaults, and this tool has its own
        // defaults domain, so without this a run that appended symbols silently became the starting point
        // for every later run — two invocations of the same command produced different PNGs.
        watchlist.resetToDefaults()
        // A list long enough to scroll is the case the scrolling branch exists for, and the shipped
        // default is four rows. STOCKBAR_UI_WATCHLIST=VCB,MBB,BTCUSDT appends real tickers so that branch
        // can be rendered at all; the market is inferred from each one, so the rows carry real prices
        // rather than a screenful of dashes.
        if let extra = ProcessInfo.processInfo.environment["STOCKBAR_UI_WATCHLIST"] {
            for field in extra.split(separator: ",") {
                watchlist.add(String(field), market: .vietnam)
            }
        }
        // STOCKBAR_UI_HOLDING=VCB:1200:58400 puts a position on a row, so the four card rows it adds can
        // be rendered — they exist only when a quantity and a cost have been typed, which a snapshot tool
        // cannot do.
        if let spec = ProcessInfo.processInfo.environment["STOCKBAR_UI_HOLDING"] {
            let parts = spec.split(separator: ":")
            if parts.count == 3, let qty = Double(parts[1]), let cost = Double(parts[2]),
               let entry = watchlist.symbols.first(where: { $0.symbol == parts[0].uppercased() }) {
                watchlist.setHoldingQuantity(entry, qty)
                watchlist.setHoldingCost(entry, cost)
            }
        }
        // STOCKBAR_UI_TOTAL=1 puts positions on several rows across two currencies, so the portfolio
        // summary and its conversion can be rendered — it is absent for every watchlist that holds
        // nothing, which is the shipped default and everything a snapshot tool can otherwise produce.
        if ProcessInfo.processInfo.environment["STOCKBAR_UI_TOTAL"] != nil {
            watchlist.add("USDVND", market: .vietnam)
            // NI225 is held so the yen exclusion is drawn, and SJC is held with a quantity but NO cost so
            // the row that stands outside the return is drawn. Both notes are unreachable otherwise, and
            // both are the whole point of the summary: they are what it says when it cannot say everything.
            watchlist.add("NI225", market: .world)
            watchlist.add("SJC", market: .vietnam)
            for (symbol, qty, cost) in [("VCB", 1_200.0, 58_400.0), ("BTCUSDT", 0.5, 60_000.0),
                                        ("NI225", 3.0, 60_000.0), ("SJC", 2.0, 0.0)] {
                guard let entry = watchlist.symbols.first(where: { $0.symbol == symbol }) else { continue }
                watchlist.setHoldingQuantity(entry, qty)
                if cost > 0 { watchlist.setHoldingCost(entry, cost) }
            }
        }
        // STOCKBAR_UI_ALERT=VCB:60000 puts a threshold on a row, because the bell indicator and the filled
        // bell in edit mode only appear when one is set, and neither can be produced by a snapshot tool
        // that cannot type into a field. `currentPrice: nil` keeps the alert armed whatever the price is
        // doing, so the rendered state does not depend on the market.
        if let spec = ProcessInfo.processInfo.environment["STOCKBAR_UI_ALERT"] {
            let parts = spec.split(separator: ":")
            if parts.count == 2, let threshold = Double(parts[1]),
               let entry = watchlist.symbols.first(where: { $0.symbol == parts[0].uppercased() }) {
                watchlist.setAlert(entry, direction: .above, threshold: threshold, currentPrice: nil)
            }
        }
        // STOCKBAR_UI_LOG=1 seeds the self-recorded series. SJC, USDVND and GOLDGAP draw a sparkline
        // only after the app has watched them change over days, which a snapshot run has not — so the
        // points are pushed through the real recorder rather than injected past it, and the PNG proves
        // the merge in QuoteReader.history rather than a fixture.
        //
        // Its own defaults suite, wiped first. Both matter and both were missing. A price log persists like
        // any other, so a second run appended the seed to the first run's copy and the "twelve-day" series
        // quietly became a twenty-four-day one — uisnap's whole value is that two runs of one command
        // produce the same PNG. And the suite keeps the seed out of the domain the real app reads.
        let suiteName = "uisnap.pricelogs"
        UserDefaults.standard.removePersistentDomain(forName: suiteName)
        let priceLogs = PriceLogStore(defaults: UserDefaults(suiteName: suiteName) ?? .standard)
        if ProcessInfo.processInfo.environment["STOCKBAR_UI_LOG"] != nil {
            // Watched as well as seeded: QuoteReader prunes every log whose row has left the watchlist, so
            // a seed for a symbol nobody is watching is deleted on the first poll and the PNG renders the
            // shipped four rows as if the feature did not exist.
            watchlist.add("SJC", market: .vietnam)
            let sjc = WatchedSymbol(symbol: "SJC", market: .vietnam, pinnedToMenuBar: false)
            var when = Date().addingTimeInterval(-12 * 86400)
            for price in [138_500_000.0, 139_200_000, 138_900_000, 140_100_000, 141_800_000,
                          141_200_000, 142_600_000, 143_400_000, 143_100_000, 144_000_000] {
                // `now: when` and not the wall clock: the recorder spaces points by when it was told it
                // looked, and ten records inside one real second would collapse to a single point.
                priceLogs.record([sjc], quotes: ["vietnam:SJC": Quote(
                    symbol: "SJC", market: .vietnam, price: price, reference: nil,
                    ceiling: nil, floor: nil, volume: nil, asOf: when)], now: when)
                when = when.addingTimeInterval(86400)
            }
        }
        let reader = QuoteReader(watchlist: watchlist, priceLogs: priceLogs)
        let updater = Updater()

        let host = NSHostingView(rootView: TickerPopover(
            reader: reader,
            watchlist: watchlist,
            updater: updater,
            checkForUpdates: {},
            quitAction: {}
        ))
        host.frame = NSRect(origin: .zero, size: host.fittingSize)

        // A window is what gives SwiftUI a live layout/appearance context; rendering a detached
        // NSHostingView yields blank or mis-sized output.
        let win = NSWindow(contentRect: host.frame,
                           styleMask: [.titled], backing: .buffered, defer: false)
        win.contentView = host
        // Key AND active, not just ordered front: AppKit draws controls in an inactive window in their
        // dimmed state, so a switch that is on renders with a grey track instead of its tint — which
        // reads as "the tint doesn't work" when the real popover is perfectly fine.
        if #available(macOS 14.0, *) { app.activate() } else { app.activate(ignoringOtherApps: true) }
        win.makeKeyAndOrderFront(nil)

        // setPanelOpen rather than refresh: sparklines are only fetched while the panel is open, so a
        // plain refresh would render rows with no chart and misrepresent what the app actually shows.
        reader.setPanelOpen(true)
        RunLoop.main.run(until: Date().addingTimeInterval(6))

        let size = host.fittingSize
        host.frame = NSRect(origin: .zero, size: size)
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.4))

        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else {
            FileHandle.standardError.write(Data("✗ could not allocate a bitmap\n".utf8))
            exit(1)
        }
        host.cacheDisplay(in: host.bounds, to: rep)

        // The panel's own background is translucent (a popover normally sits on vibrancy), so composite
        // it over the theme's window background — otherwise the PNG is unreadable in most viewers.
        let backdrop = NSImage(size: size)
        backdrop.lockFocus()
        (wantsDark ? NSColor(white: 0.13, alpha: 1) : NSColor(white: 0.96, alpha: 1)).setFill()
        NSRect(origin: .zero, size: size).fill()
        NSImage(size: size, flipped: false) { _ in rep.draw(in: NSRect(origin: .zero, size: size)) }
            .draw(in: NSRect(origin: .zero, size: size))
        backdrop.unlockFocus()

        guard let tiff = backdrop.tiffRepresentation,
              let flat = NSBitmapImageRep(data: tiff),
              let png = flat.representation(using: .png, properties: [:]) else {
            FileHandle.standardError.write(Data("✗ could not encode a PNG\n".utf8))
            exit(1)
        }
        try? png.write(to: URL(fileURLWithPath: out))
        print("panel: \(Int(size.width))×\(Int(size.height))pt (\(wantsDark ? "dark" : "light")) → \(out)")
        exit(0)
    }
}
