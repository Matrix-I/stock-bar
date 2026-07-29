// TickerPopover.swift — the panel that drops down from the menu-bar item: one row per watched symbol
// with its price, change and an intraday sparkline, then the controls for editing the watchlist.

import SwiftUI
import AppKit

/// A minimal line chart of recent closes. Deliberately axis-less and label-less: at ~90×22 points there
/// is room for the shape of the last hour and nothing else, and a shape is all this needs to answer
/// "which way has it been going".
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
                // Inset by 1pt top and bottom so a stroke at an extreme isn't clipped by the frame.
                let points: [CGPoint] = values.enumerated().map { i, v in
                    let x = geo.size.width * Double(i) / Double(values.count - 1)
                    let norm = span > 0 ? (v - lo) / span : 0.5
                    return CGPoint(x: x, y: 1 + (geo.size.height - 2) * (1 - norm))
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
                    line.stroke(color, style: StrokeStyle(lineWidth: 1.4, lineCap: .round, lineJoin: .round))
                }
            }
        }
    }
}

/// One watched symbol.
struct QuoteRow: View {
    let entry: WatchedSymbol
    let quote: Quote?
    let history: [Double]
    let stale: Bool

    private var isIndex: Bool { isIndexSymbol(entry.symbol) }

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text(entry.symbol.uppercased())
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                Text(entry.market == .vietnam ? (isIndex ? "Index" : "HOSE") : "Binance")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }
            .frame(width: 66, alignment: .leading)

            if let quote {
                Sparkline(values: history, color: bandColor(quote.band, market: quote.market))
                    .frame(width: 78, height: 22)

                Spacer(minLength: 4)

                VStack(alignment: .trailing, spacing: 1) {
                    Text(priceText(quote))
                        .font(.system(size: 12, weight: .medium))
                        .monospacedDigit()
                        .foregroundStyle(bandColor(quote.band, market: quote.market))
                        .textSelection(.enabled)
                    if let pct = quote.changePercent, let chg = quote.change {
                        Text("\(bandArrow(quote.band)) \(fmtChange(chg, market: quote.market, isIndex: isIndex)) (\(fmtChangePercent(pct)))")
                            .font(.system(size: 9))
                            .monospacedDigit()
                            .foregroundStyle(bandColor(quote.band, market: quote.market).opacity(0.85))
                    }
                }
            } else {
                Spacer()
                Text("—").foregroundStyle(.secondary).font(.system(size: 12))
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

struct TickerPopover: View {
    @ObservedObject var reader: QuoteReader
    @ObservedObject var watchlist: Watchlist
    let quitAction: () -> Void

    @State private var newSymbol = ""
    @State private var newMarket: Market = .vietnam
    @State private var editing = false
    @State private var launchAtLogin = LoginItem.isEnabled
    /// AppStorage rather than @State: AppDelegate reads this same key out of UserDefaults to decide
    /// what to draw in the menu bar, and picks the change up through its didChangeNotification observer.
    @AppStorage("showChangeInMenuBar") private var showChangeInMenuBar = true

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            Divider().padding(.vertical, 6)

            VStack(spacing: 7) {
                ForEach(watchlist.symbols) { entry in
                    HStack(spacing: 6) {
                        if editing {
                            Button {
                                watchlist.togglePinned(entry)
                            } label: {
                                Image(systemName: entry.pinnedToMenuBar ? "pin.fill" : "pin.slash")
                                    .font(.system(size: 9))
                                    .foregroundStyle(entry.pinnedToMenuBar ? Color.accentColor : .secondary)
                            }
                            .buttonStyle(.plain)
                            .help(entry.pinnedToMenuBar ? "Hide from the menu bar" : "Show in the menu bar")
                        }

                        QuoteRow(entry: entry,
                                 quote: reader.quotes[entry.id],
                                 history: reader.history[entry.id] ?? [],
                                 stale: reader.isStale(entry.id))

                        if editing {
                            Button {
                                watchlist.remove(entry)
                            } label: {
                                Image(systemName: "minus.circle.fill")
                                    .font(.system(size: 10))
                                    .foregroundStyle(.red)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }

            if editing { addRow }

            Divider().padding(.vertical, 6)

            footer
        }
        .padding(12)
        .frame(width: 320)
    }

    private var header: some View {
        HStack {
            Text("StockBar").font(.system(size: 13, weight: .semibold))
            // A snapshot build says so; a released one shows the bare version. Without this the only
            // way to tell which build is running is to inspect Info.plist by hand.
            Text(AppInfo.version)
                .font(.system(size: 9))
                .foregroundStyle(AppInfo.isSnapshot ? Color(nsColor: .systemOrange) : .secondary)
                .help(AppInfo.isSnapshot ? "Unreleased development build" : "Released build")
            if reader.isFetching {
                ProgressView().controlSize(.small).scaleEffect(0.6).frame(width: 12, height: 12)
            }
            Spacer()
            Button { editing.toggle() } label: {
                Image(systemName: editing ? "checkmark" : "square.and.pencil").font(.system(size: 10))
            }
            .buttonStyle(.plain)
            .help(editing ? "Done" : "Edit the watchlist")

            Button { reader.refresh() } label: {
                Image(systemName: "arrow.clockwise").font(.system(size: 10))
            }
            .buttonStyle(.plain)
            .help("Refresh now")
        }
    }

    private var addRow: some View {
        HStack(spacing: 6) {
            Picker("", selection: $newMarket) {
                Text("VN").tag(Market.vietnam)
                Text("Crypto").tag(Market.crypto)
            }
            .labelsHidden()
            .frame(width: 84)

            TextField(newMarket == .vietnam ? "VCB / VNINDEX" : "BTCUSDT", text: $newSymbol)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 11))
                .onSubmit(addSymbol)

            Button("Add", action: addSymbol)
                .disabled(newSymbol.trimmingCharacters(in: .whitespaces).isEmpty)
                .controlSize(.small)
        }
        .padding(.top, 8)
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 6) {
            // The session line is the answer to "why isn't the price moving?" — without it a closed
            // market is indistinguishable from a broken feed.
            HStack(spacing: 6) {
                Circle()
                    .fill(MarketHours.isOpen(.vietnam) ? Color.green : Color.secondary)
                    .frame(width: 6, height: 6)
                Text(MarketHours.statusText(for: .vietnam))
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                Spacer()
                if let at = reader.lastSuccessAt {
                    Text(fmtAsOf(at)).font(.system(size: 10)).foregroundStyle(.secondary)
                }
            }

            if let err = reader.lastError {
                Text(err)
                    .font(.system(size: 10))
                    .foregroundStyle(.orange)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Toggle(isOn: $showChangeInMenuBar) {
                Text("Show change % in the menu bar").font(.system(size: 11))
            }
            .toggleStyle(.checkbox)

            Toggle(isOn: $launchAtLogin) {
                Text("Launch at login").font(.system(size: 11))
            }
            .toggleStyle(.checkbox)
            .onChange(of: launchAtLogin) { LoginItem.setEnabled($0) }

            HStack {
                Spacer()
                Button("Quit StockBar", action: quitAction)
                    .controlSize(.small)
            }
        }
    }

    private func addSymbol() {
        watchlist.add(newSymbol, market: newMarket)
        newSymbol = ""
    }
}
