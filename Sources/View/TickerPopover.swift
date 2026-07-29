// TickerPopover.swift — the panel that drops down from the menu-bar item: one row per watched symbol
// with its price, change and an intraday sparkline, then the controls for editing the watchlist.

import SwiftUI
import AppKit

// MARK: - Scale

/// Everything in this panel is sized through `pt`/`uiFont`, which multiply by this.
///
/// The panel was asked to render its text 50% larger. Scaling only the fonts would have clipped the
/// columns — a 66pt symbol column cannot hold "BTCUSDT" at 18pt, and the change line would have gone
/// back to reading "+24.06 (+…" — so the widths, padding and spacing scale with them. Keeping the
/// original numbers at each call site means the ratios between elements stay readable, and the factor is
/// a single edit rather than forty.
private let uiScale: CGFloat = 1.5

/// A scaled point value, for frames, padding and spacing.
private func pt(_ value: CGFloat) -> CGFloat { value * uiScale }

/// A scaled system font.
private func uiFont(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
    .system(size: size * uiScale, weight: weight)
}

/// The settings block below the last divider is deliberately a fifth smaller than the rows above it. It is
/// chrome you set once rather than data you read, and at the panel's 1.5× scale it was competing with the
/// prices for attention. Expressed as a factor instead of pre-shrunk literals so the numbers at each call
/// site stay directly comparable with the rows' own `uiFont(...)` sizes.
private let footerScale: CGFloat = 0.8

/// A scaled system font for the footer's settings block.
private func footerFont(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
    uiFont(size * footerScale, weight)
}

// MARK: - Sparkline

/// A minimal line chart of recent closes. Deliberately axis-less and label-less: there is room for the
/// shape of the last session and nothing else, and a shape is all this needs to answer "which way has it
/// been going".
struct Sparkline: View {
    let values: [Double]
    let color: Color

    var body: some View {
        // Two points is the minimum that draws a line; below that render nothing rather than a dot,
        // which would read as a flat session.
        if values.count < 2 {
            Rectangle().fill(.clear)
        } else {
            GeometryReader { geo in
                let lo = values.min() ?? 0
                let hi = values.max() ?? 1
                // A dead-flat series (a stock that hasn't moved all session) would divide by zero on
                // the normalisation below; pin it to the vertical centre instead.
                let span = hi - lo
                // Inset top and bottom so a stroke at an extreme isn't clipped by the frame.
                let inset = pt(1)
                let points: [CGPoint] = values.enumerated().map { i, v in
                    let x = geo.size.width * Double(i) / Double(values.count - 1)
                    let norm = span > 0 ? (v - lo) / span : 0.5
                    return CGPoint(x: x, y: inset + (geo.size.height - inset * 2) * (1 - norm))
                }
                let line = Path { p in p.addLines(points) }
                // A faint fill under the line gives the eye a baseline to read the slope against
                // without spending pixels on an axis: the same points, closed down to the bottom edge.
                let area = Path { p in
                    p.addLines(points)
                    p.addLine(to: CGPoint(x: geo.size.width, y: geo.size.height))
                    p.addLine(to: CGPoint(x: 0, y: geo.size.height))
                    p.closeSubpath()
                }
                ZStack {
                    area.fill(color.opacity(0.14))
                    line.stroke(color, style: StrokeStyle(lineWidth: pt(1.4), lineCap: .round, lineJoin: .round))
                }
            }
        }
    }
}

// MARK: - Row

/// One watched symbol.
struct QuoteRow: View {
    let entry: WatchedSymbol
    let quote: Quote?
    let history: [Double]
    let stale: Bool
    /// Dropped while the watchlist is being edited. The edit controls (pin, up, down, remove) claim real
    /// width, and keeping the chart alongside them truncated the change line to "+24.06 (+…" on the index
    /// rows and wrapped it onto a second line on the others, making the rows different heights. The chart
    /// is the least useful thing on screen while you're reordering a list, so it yields.
    var showSparkline = true

    private var isIndex: Bool { isIndexSymbol(entry.symbol) }

    var body: some View {
        HStack(spacing: pt(10)) {
            VStack(alignment: .leading, spacing: pt(1)) {
                Text(entry.symbol.uppercased())
                    .font(uiFont(12, .semibold))
                    .lineLimit(1)
                Text(entry.market == .vietnam ? (isIndex ? "Index" : "HOSE") : "Binance")
                    .font(uiFont(9))
                    .foregroundStyle(.secondary)
            }
            .frame(width: pt(66), alignment: .leading)

            if let quote {
                if showSparkline {
                    Sparkline(values: history, color: bandColor(quote.band, market: quote.market))
                        .frame(width: pt(78), height: pt(22))
                }

                Spacer(minLength: pt(4))

                VStack(alignment: .trailing, spacing: pt(1)) {
                    Text(priceText(quote))
                        .font(uiFont(12, .medium))
                        .monospacedDigit()
                        .foregroundStyle(bandColor(quote.band, market: quote.market))
                        .textSelection(.enabled)
                    if let pct = quote.changePercent, let chg = quote.change {
                        Text("\(bandArrow(quote.band)) \(fmtChange(chg, market: quote.market, isIndex: isIndex)) (\(fmtChangePercent(pct)))")
                            .font(uiFont(9))
                            .monospacedDigit()
                            .foregroundStyle(bandColor(quote.band, market: quote.market).opacity(0.85))
                            // Never wrap or ellipsise: this line is the whole point of the row, and a
                            // second line would make neighbouring rows different heights.
                            .lineLimit(1)
                            .fixedSize()
                    }
                }
            } else {
                Spacer()
                Text("—").foregroundStyle(.secondary).font(uiFont(12))
            }
        }
        .opacity(stale ? 0.5 : 1)
        .help(helpText)
    }

    private func priceText(_ q: Quote) -> String {
        fmtPrice(q.price, market: q.market, isIndex: isIndex)
    }

    /// The tooltip carries what doesn't fit in the row: the daily band, volume, and how old the quote
    /// is. Ceiling/floor especially — those are the numbers a VN trader wants when a stock locks up.
    private var helpText: String {
        guard let q = quote else { return "No data yet" }
        var parts: [String] = []
        if let c = q.ceiling { parts.append("Trần \(fmtPrice(c, market: q.market, isIndex: false))") }
        if let f = q.floor { parts.append("Sàn \(fmtPrice(f, market: q.market, isIndex: false))") }
        if let r = q.reference {
            let label = q.market == .vietnam ? "TC" : "24h open"
            parts.append("\(label) \(fmtPrice(r, market: q.market, isIndex: isIndex))")
        }
        if let v = q.volume { parts.append("Vol \(fmtVolume(v))") }
        parts.append(fmtAsOf(q.asOf))
        return parts.joined(separator: " · ")
    }
}

// MARK: - Height measurement

/// The unclipped height the symbol list wants, so the panel can decide for itself whether to scroll.
///
/// A `ScrollView` reports no useful height of its own, so it cannot be handed an open-ended constraint
/// here: the popover sizes itself to its SwiftUI content, and a ScrollView asked for its ideal height in
/// that situation answers with roughly nothing — the panel would collapse. Measuring the content and
/// then giving the ScrollView a concrete height is what avoids that.
private struct ListHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    /// `max`, not last-one-wins: the background GeometryReader emits a spurious 0 alongside the real
    /// height during an early layout pass, and letting that through leaves the measurement stuck at zero
    /// so the list never switches to the scrolling branch. Every pass recomputes from scratch, so a
    /// shrinking list is still tracked.
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

/// Height of the pinned header, measured the same way and for the same reason as the list.
private struct HeaderHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

/// Height of the pinned footer. Measured rather than estimated so it keeps up with the rows that come
/// and go inside it — the add field while editing, the error line when a fetch fails.
private struct FooterHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

// MARK: - Panel

struct TickerPopover: View {
    @ObservedObject var reader: QuoteReader
    @ObservedObject var watchlist: Watchlist
    /// Sparkle updater — backs the automatic-check toggle in the footer. @ObservedObject, not a plain
    /// `let`: the toggle's value lives inside SPUUpdater, so without observing this the switch would
    /// write the new value and redraw from the old one.
    @ObservedObject var updater: Updater
    /// Closes this popover and starts a user-initiated Sparkle check; supplied by AppDelegate. The
    /// popover has to close first: it is `.applicationDefined`, so it would otherwise stay open on top
    /// of the update window it just spawned.
    let checkForUpdates: () -> Void
    let quitAction: () -> Void

    @State private var newSymbol = ""
    @State private var newMarket: Market = .vietnam
    /// A symbol check is in flight. Blocks a second Add so one Enter-mash can't fire several checks.
    @State private var checking = false
    /// Why the last Add didn't go through, shown under the field. nil while there is nothing to say.
    /// Seeded from the environment for the same reason as `editing` below: the message only appears in
    /// response to a rejected click, which a snapshot tool cannot perform, and an unrenderable state is
    /// an unverifiable one. Never set for the app itself.
    @State private var addError: String? = ProcessInfo.processInfo.environment["STOCKBAR_UI_ADD_ERROR"]
    /// Edit mode. The environment check exists so Tools/uisnap.sh can render this state: an edit row
    /// carries four controls beside a price, which is exactly the layout worth checking, and it is
    /// unreachable from a snapshot tool otherwise. The variable is never set for the app itself, so this
    /// is always false in a real launch.
    @State private var editing = ProcessInfo.processInfo.environment["STOCKBAR_UI_EDIT"] != nil
    @State private var launchAtLogin = LoginItem.isEnabled
    /// AppStorage rather than @State: AppDelegate reads this same key out of UserDefaults to decide
    /// what to draw in the menu bar, and picks the change up through its didChangeNotification observer.
    @AppStorage("showChangeInMenuBar") private var showChangeInMenuBar = true

    /// visibleFrame height of the display the popover is actually shown on, reported by
    /// PanelScreenReporter. Seeded with the menu-bar screen so the first layout pass already has a
    /// sensible number to cap against.
    @State private var panelScreenHeight: CGFloat = TickerPopover.initialScreenHeight
    @State private var listHeight: CGFloat = 0
    @State private var headerHeight: CGFloat = 0
    @State private var footerHeight: CGFloat = 0

    /// How much of the screen the whole panel may occupy before the list starts scrolling instead of
    /// pushing the popover further down.
    private static let panelHeightFraction: CGFloat = 0.9

    /// The tallest the symbol list may get: whatever the screen can spare once the pinned header, the
    /// pinned footer and this panel's own outer padding have taken their share. The floor keeps a few
    /// rows visible on a short display rather than letting the footer squeeze the list to nothing.
    private var maxListHeight: CGFloat {
        let chrome = headerHeight + footerHeight + pt(12) * 2
        return max(pt(120), panelScreenHeight * Self.panelHeightFraction - chrome)
    }

    /// Best guess before the popover's window exists: the display that owns the menu bar, identified by
    /// its frame origin sitting at (0,0) in AppKit's global space. That is stable, unlike the order of
    /// `NSScreen.screens` or `NSScreen.main`, which follows keyboard focus.
    private static var initialScreenHeight: CGFloat {
        let menuBarScreen = NSScreen.screens.first { $0.frame.origin == .zero }
            ?? NSScreen.screens.first
            ?? NSScreen.main
        return menuBarScreen?.visibleFrame.height ?? 800
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            pinnedHeader

            // Render un-scrolled by default — identical to the plain auto-sizing stack this panel used to
            // be — so the very first layout pass always has a well-defined height and the popover opens at
            // its natural size. Only once the list has measured taller than the room the screen can spare
            // does it switch to a ScrollView, and then with a concrete height (see ListHeightKey).
            if listHeight > maxListHeight {
                ScrollView(.vertical) {
                    symbolList.background(OverlayScrollerConfigurator())
                }
                .frame(height: maxListHeight)
            } else {
                symbolList
            }

            pinnedFooter
        }
        // Only the vertical padding belongs to the panel. The horizontal padding is applied inside each
        // region — including inside the scroll area — so the ScrollView spans the panel's full width and
        // the overlay scroller has a gutter of its own to sit in. With the padding out here the scroll
        // view ended exactly where the content did, and the scroller was drawn on top of the change
        // figures at the right-hand edge. maxListHeight subtracts this same pt(12) * 2.
        .padding(.vertical, pt(12))
        .frame(width: pt(320))
        .background(PanelScreenReporter { panelScreenHeight = $0 })
    }

    /// The watched symbols — the only part of the panel that scrolls. Everything else stays pinned, so
    /// Refresh, the add field and Quit remain reachable however long the list grows.
    private var symbolList: some View {
        VStack(spacing: pt(7)) {
            ForEach(Array(watchlist.symbols.enumerated()), id: \.element.id) { index, entry in
                HStack(spacing: pt(6)) {
                    if editing {
                        Button {
                            watchlist.togglePinned(entry)
                        } label: {
                            Image(systemName: entry.pinnedToMenuBar ? "pin.fill" : "pin.slash")
                                .font(uiFont(9))
                                .foregroundStyle(entry.pinnedToMenuBar ? Color.accentColor : .secondary)
                        }
                        .buttonStyle(.plain)
                        .help(entry.pinnedToMenuBar ? "Hide from the menu bar" : "Show in the menu bar")

                        // Reorder. Stacked vertically so the pair costs one button's width instead of
                        // two — this row already carries a symbol, a price and two other buttons.
                        VStack(spacing: 0) {
                            reorderButton("chevron.up", disabled: index == 0) {
                                watchlist.moveUp(entry)
                            }
                            reorderButton("chevron.down", disabled: index == watchlist.symbols.count - 1) {
                                watchlist.moveDown(entry)
                            }
                        }
                    }

                    QuoteRow(entry: entry,
                             quote: reader.quotes[entry.id],
                             history: reader.history[entry.id] ?? [],
                             stale: reader.isStale(entry.id),
                             showSparkline: !editing)

                    if editing {
                        Button {
                            watchlist.remove(entry)
                        } label: {
                            Image(systemName: "minus.circle.fill")
                                .font(uiFont(10))
                                .foregroundStyle(.red)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        // Inside the scroll area on purpose — see the note on the panel's own padding.
        .padding(.horizontal, pt(12))
        .fixedSize(horizontal: false, vertical: true)
        .background(GeometryReader { proxy in
            Color.clear.preference(key: ListHeightKey.self, value: proxy.size.height)
        })
        .onPreferenceChange(ListHeightKey.self) { listHeight = $0 }
    }

    /// The header and its divider, measured so the scroll area below knows how much room is left.
    private var pinnedHeader: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().padding(.vertical, pt(6))
        }
        .padding(.horizontal, pt(12))
        .fixedSize(horizontal: false, vertical: true)
        .background(GeometryReader { proxy in
            Color.clear.preference(key: HeaderHeightKey.self, value: proxy.size.height)
        })
        .onPreferenceChange(HeaderHeightKey.self) { headerHeight = $0 }
    }

    /// The add field, the divider and the settings. Outside the scroll area on purpose: on a list long
    /// enough to scroll, adding a symbol would otherwise mean scrolling to the bottom to reach the field,
    /// and Quit would be just as far away.
    private var pinnedFooter: some View {
        VStack(alignment: .leading, spacing: 0) {
            if editing { addRow }
            Divider().padding(.vertical, pt(6))
            footer
        }
        .padding(.horizontal, pt(12))
        .fixedSize(horizontal: false, vertical: true)
        .background(GeometryReader { proxy in
            Color.clear.preference(key: FooterHeightKey.self, value: proxy.size.height)
        })
        .onPreferenceChange(FooterHeightKey.self) { footerHeight = $0 }
    }

    private var header: some View {
        HStack {
            Text("StockBar").font(uiFont(13, .semibold))
            // A snapshot build says so; a released one shows the bare version. Without this the only
            // way to tell which build is running is to inspect Info.plist by hand.
            Text(AppInfo.version)
                .font(uiFont(9))
                .foregroundStyle(AppInfo.isSnapshot ? Color(nsColor: .systemOrange) : .secondary)
                .help(AppInfo.isSnapshot ? "Unreleased development build" : "Released build")
            if reader.isFetching {
                ProgressView()
                    .controlSize(.small)
                    .scaleEffect(0.6 * uiScale)
                    .frame(width: pt(12), height: pt(12))
            }
            Spacer()
            Button { editing.toggle() } label: {
                Image(systemName: editing ? "checkmark" : "square.and.pencil").font(uiFont(10))
            }
            .buttonStyle(.plain)
            .help(editing ? "Done" : "Edit the watchlist")

            Button { reader.refresh() } label: {
                Image(systemName: "arrow.clockwise").font(uiFont(10))
            }
            .buttonStyle(.plain)
            .help("Refresh now")
        }
    }

    private var addRow: some View {
        VStack(alignment: .leading, spacing: pt(4)) {
            HStack(spacing: pt(6)) {
                Picker("", selection: $newMarket) {
                    Text("VN").tag(Market.vietnam)
                    Text("Crypto").tag(Market.crypto)
                }
                .labelsHidden()
                .frame(width: pt(84))

                // Typing clears the last verdict: leaving "XYZ isn't listed" under a field that now reads
                // something else accuses the wrong symbol. Done through the binding rather than
                // .onChange(of:perform:), which is deprecated, while its replacement is macOS 14+.
                TextField(newMarket == .vietnam ? "VCB / VNINDEX" : "BTCUSDT",
                          text: Binding(get: { newSymbol },
                                        set: { newSymbol = $0; addError = nil }))
                    .textFieldStyle(.roundedBorder)
                    .font(uiFont(11))
                    .onSubmit(addSymbol)
                    // Deliberately NOT disabled while a check runs: disabling a focused text field drops
                    // the focus ring, so a rejected symbol would leave the caret gone and the field
                    // needing another click before it could be corrected. addSymbol guards instead.

                if checking {
                    ProgressView()
                        .scaleEffect(0.6 * uiScale)
                        .frame(width: pt(12), height: pt(12))
                }

                Button("Add", action: addSymbol)
                    .disabled(checking || newSymbol.trimmingCharacters(in: .whitespaces).isEmpty)
            }

            if let addError {
                Text(addError)
                    .font(uiFont(9))
                    .foregroundStyle(.orange)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.top, pt(8))
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: pt(6)) {
            // The session line is the answer to "why isn't the price moving?" — without it a closed
            // market is indistinguishable from a broken feed.
            HStack(spacing: pt(6)) {
                Circle()
                    .fill(MarketHours.isOpen(.vietnam) ? Color.green : Color.secondary)
                    .frame(width: pt(6), height: pt(6))
                Text(MarketHours.statusText(for: .vietnam))
                    .font(footerFont(10))
                    .foregroundStyle(.secondary)
                Spacer()
                if let at = reader.lastSuccessAt {
                    Text(fmtAsOf(at)).font(footerFont(10)).foregroundStyle(.secondary)
                }
            }

            if let err = reader.lastError {
                Text(err)
                    .font(footerFont(10))
                    .foregroundStyle(.orange)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            switchRow("Show change % in the menu bar", isOn: $showChangeInMenuBar)

            // The @State mirror is what makes the switch move: LoginItem reads its state from
            // SMAppService, which publishes nothing, so a binding straight onto it would flip the login
            // item and then redraw from the old value.
            switchRow("Launch at login", isOn: Binding(
                get: { launchAtLogin },
                set: { launchAtLogin = $0; LoginItem.setEnabled($0) }
            ))

            // Sparkle persists this itself, so it is a direct binding onto the updater rather than an
            // @AppStorage key of ours that would have to be kept in step with Sparkle's own default.
            switchRow("Automatically check for updates", isOn: Binding(
                get: { updater.automaticallyChecks },
                set: { updater.automaticallyChecks = $0 }
            ))

            Button(action: checkForUpdates) {
                Text("Check for updates…").font(footerFont(11))
            }
            .buttonStyle(.link)

            HStack {
                Spacer()
                Button("Quit", action: quitAction)
            }
        }
    }

    /// One half of the up/down reorder control. Disabled rather than hidden at the ends of the list, so
    /// the rows stay aligned instead of shifting sideways on the first and last entry.
    private func reorderButton(_ symbol: String, disabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(uiFont(7, .bold))
                .frame(width: pt(11), height: pt(8))
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .foregroundStyle(disabled ? Color.secondary.opacity(0.3) : .secondary)
        .help(symbol == "chevron.up" ? "Move up" : "Move down")
    }

    /// A settings row: label on the left, switch on the right. Same shape as stats-bar's Control Center
    /// so the two apps' panels read alike — and a switch states its on/off position at a glance, which a
    /// checkbox in a dark popover does less well.
    private func switchRow(_ label: String, isOn: Binding<Bool>) -> some View {
        HStack {
            Text(label).font(footerFont(11))
            Spacer(minLength: pt(12))
            Toggle(label, isOn: isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .tint(.green)
        }
    }

    /// Check the symbol with the venue before it joins the list, and say so when it doesn't exist.
    ///
    /// The list used to accept anything typed into it. A misspelled ticker is not rejected by the
    /// upstreams — the VN board just omits the row and Binance answers 400 — so it landed in the
    /// watchlist and rendered a dash indefinitely, which looks identical to a feed that is down. The one
    /// moment the difference can still be explained is here, before the row exists.
    private func addSymbol() {
        let typed = newSymbol.trimmingCharacters(in: .whitespaces).uppercased()
        guard !typed.isEmpty, !checking else { return }
        // The ticker itself overrules the picker, so BTCUSDT typed against the "VN" default is checked
        // against Binance rather than being reported as an unlisted Vietnamese equity. See Market.inferred.
        let market = Market.inferred(for: typed) ?? newMarket

        // Caught here rather than left to Watchlist.add, which drops a duplicate silently — from the
        // field that is indistinguishable from a rejection, with nothing said either way.
        if watchlist.symbols.contains(where: { $0.symbol == typed && $0.market == market }) {
            addError = "\(typed) is already in the list"
            return
        }

        checking = true
        addError = nil
        Task {
            let verdict = await reader.validate(typed, market: market)
            checking = false
            switch verdict {
            case .ok:
                watchlist.add(typed, market: market)
                newSymbol = ""
            case .unknown:
                addError = market == .vietnam
                    ? "\(typed) isn't listed on HOSE/HNX — check the ticker."
                    : "\(typed) isn't a pair on Binance — check the ticker."
            case .unreachable(let why):
                // Not added. The symbol may well be real, but adding it on an unverified guess is how the
                // permanent-dash row got here in the first place; the message names the check as the thing
                // that failed, and pressing Add again retries it.
                addError = "Couldn't check \(typed) — \(why). Try again."
            }
        }
    }
}
