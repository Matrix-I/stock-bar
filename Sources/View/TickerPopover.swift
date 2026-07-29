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
    /// Edit mode. The environment check exists so Tools/uisnap.sh can render this state: an edit row
    /// carries four controls beside a price, which is exactly the layout worth checking, and it is
    /// unreachable from a snapshot tool otherwise. The variable is never set for the app itself, so this
    /// is always false in a real launch.
    @State private var editing = ProcessInfo.processInfo.environment["STOCKBAR_UI_EDIT"] != nil
    @State private var launchAtLogin = LoginItem.isEnabled
    /// AppStorage rather than @State: AppDelegate reads this same key out of UserDefaults to decide
    /// what to draw in the menu bar, and picks the change up through its didChangeNotification observer.
    @AppStorage("showChangeInMenuBar") private var showChangeInMenuBar = true

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            Divider().padding(.vertical, pt(6))

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

            if editing { addRow }

            Divider().padding(.vertical, pt(6))

            footer
        }
        .padding(pt(12))
        .frame(width: pt(320))
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
        HStack(spacing: pt(6)) {
            Picker("", selection: $newMarket) {
                Text("VN").tag(Market.vietnam)
                Text("Crypto").tag(Market.crypto)
            }
            .labelsHidden()
            .frame(width: pt(84))

            TextField(newMarket == .vietnam ? "VCB / VNINDEX" : "BTCUSDT", text: $newSymbol)
                .textFieldStyle(.roundedBorder)
                .font(uiFont(11))
                .onSubmit(addSymbol)

            Button("Add", action: addSymbol)
                .disabled(newSymbol.trimmingCharacters(in: .whitespaces).isEmpty)
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
                    .font(uiFont(10))
                    .foregroundStyle(.secondary)
                Spacer()
                if let at = reader.lastSuccessAt {
                    Text(fmtAsOf(at)).font(uiFont(10)).foregroundStyle(.secondary)
                }
            }

            if let err = reader.lastError {
                Text(err)
                    .font(uiFont(10))
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
                Text("Check for updates…").font(uiFont(11))
            }
            .buttonStyle(.link)

            HStack {
                Spacer()
                Button("Quit StockBar", action: quitAction)
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
            Text(label).font(uiFont(11))
            Spacer(minLength: pt(12))
            Toggle(label, isOn: isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .tint(.green)
        }
    }

    private func addSymbol() {
        watchlist.add(newSymbol, market: newMarket)
        newSymbol = ""
    }
}
