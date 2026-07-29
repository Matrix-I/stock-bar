// AppKitBridges.swift — the AppKit plumbing the SwiftUI panel needs but SwiftUI cannot express on its
// own: which display the popover ended up on, and thin overlay scrollers on the backing NSScrollView.

import SwiftUI
import AppKit

/// Reports the usable height of the display the popover is actually shown on, so the panel can cap its
/// scroll area against that screen instead of a guessed one. A menu-bar popover opens on whichever
/// display currently owns the menu bar, which in a multi-monitor setup is not necessarily
/// `NSScreen.main` — that one follows keyboard focus.
final class PanelScreenView: NSView {
    var onScreenHeight: ((CGFloat) -> Void)?
    private var lastReported: CGFloat = 0

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        NotificationCenter.default.removeObserver(self)
        if let window {
            // NSPopover builds its window once and reuses it, so this method does not fire again on the
            // second open — a window that later shows up on another display changes screen without ever
            // re-entering here, and only the notification catches that.
            NotificationCenter.default.addObserver(self, selector: #selector(screenChanged),
                                                   name: NSWindow.didChangeScreenNotification,
                                                   object: window)
        }
        report()
    }

    @objc private func screenChanged() {
        // Deferred: the window's `screen` is not yet the new one while the notification is being posted.
        DispatchQueue.main.async { [weak self] in self?.report() }
    }

    private func report() {
        guard let height = window?.screen?.visibleFrame.height, height > 0, height != lastReported else { return }
        lastReported = height
        onScreenHeight?(height)
    }

    deinit { NotificationCenter.default.removeObserver(self) }
}

struct PanelScreenReporter: NSViewRepresentable {
    let onScreenHeight: (CGFloat) -> Void

    func makeNSView(context: Context) -> PanelScreenView {
        let view = PanelScreenView()
        view.onScreenHeight = onScreenHeight
        return view
    }

    func updateNSView(_ nsView: PanelScreenView, context: Context) {
        nsView.onScreenHeight = onScreenHeight
    }
}

/// Placed inside a SwiftUI `ScrollView`, this walks up to the backing `NSScrollView` and forces the thin
/// *overlay* scrollers. Without it, a system set to "Show scroll bars: Always" gets the wide legacy
/// scroller — a permanent ~15pt track carved out of a panel whose rows already end in a right-aligned
/// price. Overlay scrollers are about half that and auto-hide.
struct OverlayScrollerConfigurator: NSViewRepresentable {
    final class FinderView: NSView {
        private func apply() {
            guard let scrollView = enclosingScrollView else { return }
            scrollView.scrollerStyle = .overlay
            scrollView.verticalScroller?.controlSize = .small
        }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            DispatchQueue.main.async { [weak self] in self?.apply() }
        }
        override func viewDidMoveToSuperview() {
            super.viewDidMoveToSuperview()
            DispatchQueue.main.async { [weak self] in self?.apply() }
        }
    }

    func makeNSView(context: Context) -> FinderView { FinderView(frame: .zero) }
    func updateNSView(_ nsView: FinderView, context: Context) {}
}
