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
        let reader = QuoteReader(watchlist: watchlist)
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
