// probe.swift — a command-line harness that exercises the app's data layer and prints what it got.
// Not part of the app: build_app.sh globs Sources/ only, so this file is never compiled into the
// bundle. It exists because a menu-bar app gives you nowhere to look when a fetch misbehaves.
//
// Run:
//   ./Tools/probe.sh                     # the shipped defaults
//   ./Tools/probe.sh VCB BTCUSDT DJI     # specific symbols; the venue is inferred the way the app does it

import Foundation
import AppKit

/// Pad/align a table row by hand. NOT String(format:) with %s — a Swift String bridged into a C
/// `%s` conversion is a segfault, and width specifiers on `%@` are unreliable. Padding is counted in
/// Characters so the box-drawing and "—" placeholders line up like the ASCII does.
private func row(_ symbol: String, _ price: String, _ ref: String,
                 _ change: String, _ band: String, _ menuBar: String) -> String {
    func pad(_ s: String, _ width: Int, right: Bool = false) -> String {
        let gap = max(0, width - s.count)
        return right ? String(repeating: " ", count: gap) + s : s + String(repeating: " ", count: gap)
    }
    return [pad(symbol, 10), pad(price, 12, right: true), pad(ref, 12, right: true),
            pad(change, 10, right: true), pad(band, 10, right: true), " " + menuBar].joined(separator: " ")
}

/// The venue behind a market, the way QuoteReader resolves it. Duplicated here rather than exposed from the
/// store, whose copy is private to an @MainActor class the probe has no reason to instantiate.
private func source(for market: Market) -> QuoteSource {
    switch market {
    case .vietnam: return VNQuoteSource()
    case .crypto:  return CryptoQuoteSource()
    case .world:   return WorldQuoteSource()
    }
}

@main
struct Probe {
    static func main() async {
        let args = Array(CommandLine.arguments.dropFirst())
        // Inferred exactly as the app does it, so a probe of DJI exercises the same routing decision the
        // Add field makes — a hand-rolled suffix test here is how the probe and the app come to disagree
        // about which backend owns a symbol.
        let requested: [(String, Market)] = args.isEmpty
            ? Watchlist.shipped.map { ($0.symbol, $0.market) }
            : args.map { arg in
                let s = Ticker.canonical(arg)
                return (s, Market.inferred(for: s) ?? .vietnam)
            }

        print("StockBar data probe · \(Date())")
        print("HOSE session: \(MarketHours.statusText(for: .vietnam))")
        print("World:        \(MarketHours.statusText(for: .world))")
        print(String(repeating: "─", count: 78))

        var quotes: [Quote] = []

        // The tracked list, exactly as QuoteReader plans it: asking for GOLDGAP alone has to pull in the
        // three rows it is computed from, or the probe would report "no data" for a row that works.
        let tracked = DerivedQuote.tracked(requested.map {
            WatchedSymbol(symbol: $0.0, market: $0.1, pinnedToMenuBar: false)
        })

        for market in Market.allCases {
            let symbols = tracked
                .filter { $0.market == market && !DerivedQuote.isDerived($0.symbol) }
                .map(\.symbol)
            guard !symbols.isEmpty else { continue }
            let label = market.shortLabel.padding(toLength: 6, withPad: " ", startingAt: 0)
            do {
                let t0 = Date()
                let got = try await source(for: market).fetchQuotes(for: symbols)
                print(String(format: "%@ %2d/%2d symbols in %.2fs", label, got.count, symbols.count,
                             Date().timeIntervalSince(t0)))
                quotes += got
                let missing = Set(symbols).subtracting(got.map { $0.symbol })
                if !missing.isEmpty { print("       ⚠ no data: \(missing.sorted().joined(separator: ", "))") }
            } catch {
                print("\(label) ✗ \(error.localizedDescription)")
            }
        }

        // The computed rows, from the fetched ones, keyed the way the reader keys them. Done here rather
        // than left to the panel so the arithmetic is checkable against the inputs printed just below it.
        var byID: [String: Quote] = [:]
        for q in quotes { byID["\(q.market.rawValue):\(q.symbol.uppercased())"] = q }
        quotes += DerivedQuote.values(for: tracked, from: byID).values

        print(String(repeating: "─", count: 78))
        print(row("SYMBOL", "PRICE", "REF", "CHANGE", "BAND", "MENU BAR"))

        for q in quotes.sorted(by: { $0.symbol < $1.symbol }) {
            let price = PriceFormat.price(q.price, market: q.market, isIndex: q.isIndex)
            let ref = q.reference.map { PriceFormat.price($0, market: q.market, isIndex: q.isIndex) } ?? "—"
            let chg = q.changePercent.map { PriceFormat.percent($0) } ?? "—"
            // The exact string the menu bar would render. The price and percentage come from the same
            // formatters as the PRICE/CHANGE columns above, so if this column ever disagrees with them
            // the shared-formatter rule has been broken somewhere.
            let label = WatchedSymbol(symbol: q.symbol, market: q.market, pinnedToMenuBar: true).menuBarLabel
            let menuBar = "\(label) \(price) \(chg)"
            print(row(q.symbol, price, ref, chg, "\(q.band)", menuBar))
        }

        // Sparklines are fetched separately by the reader (only while the popover is open), so check
        // them separately too.
        print(String(repeating: "─", count: 78))
        for (symbol, market) in requested {
            do {
                let closes = try await source(for: market).fetchHistory(for: symbol)
                let range = closes.isEmpty ? "—" : "\(closes.min()!) … \(closes.max()!)"
                print("history \(symbol): \(closes.count) bars, range \(range)")
            } catch {
                print("history \(symbol): ✗ \(error.localizedDescription)")
            }
        }

        // Trailing per-share figures, which back the P/E and P/B in the detail card. Printed with the
        // recovered book value and both ratios spelled out, because a ratio that looks wrong on screen is
        // only diagnosable if you can see which of the three inputs it came from — and because the feed's
        // own pe/pb are deliberately NOT what the card shows (see Core/Fundamentals.swift).
        let fundamentalsFeed = FundamentalsSource()
        print(String(repeating: "─", count: 78))
        // The same predicate the reader uses, so the probe cannot ask for a figure the app never would.
        // SSI answers for "SJC" with numbers belonging to some other company entirely, which is exactly
        // what `hasPerShareFundamentals` exists to keep off a gold row.
        for (symbol, market) in requested
        where WatchedSymbol(symbol: symbol, market: market, pinnedToMenuBar: false).hasPerShareFundamentals {
            do {
                let f = try await fundamentalsFeed.fetch(for: symbol)
                guard !f.isEmpty else { print("fundamentals \(symbol): none reported"); continue }
                let price = quotes.first { $0.symbol == symbol }?.price
                let eps = f.earningsPerShare.map { PriceFormat.price($0, market: .vietnam, isIndex: false) } ?? "—"
                let bvps = f.bookValuePerShare.map { PriceFormat.price($0, market: .vietnam, isIndex: false) } ?? "—"
                let pe = price.flatMap { f.priceEarnings(at: $0) }.map { PriceFormat.ratio($0) } ?? "—"
                let pb = price.flatMap { f.priceBook(at: $0) }.map { PriceFormat.ratio($0) } ?? "—"
                print("fundamentals \(symbol): eps \(eps) · bvps \(bvps) · P/E \(pe) · P/B \(pb)"
                      + (f.year.map { " (\($0))" } ?? ""))
            } catch {
                print("fundamentals \(symbol): ✗ \(error.localizedDescription)")
            }
        }

        // Render the real menu-bar glyph to a PNG. The status-bar image is otherwise the one part of
        // the app you cannot inspect without taking a screenshot of the whole display — this renders it
        // through the same MenuBarGlyph the app uses, so colour, spacing and total width can be
        // checked directly.
        if let out = ProcessInfo.processInfo.environment["GLYPH_OUT"] {
            // GLYPH_DEMO renders one synthetic quote per PriceBand instead of the live ones. Live data
            // is almost never simultaneously up, down, ceiling-locked and floor-locked, so this is the
            // only practical way to eyeball the whole Vietnamese colour convention at once — green up,
            // red down, purple trần, cyan sàn, yellow tham chiếu.
            if ProcessInfo.processInfo.environment["GLYPH_DEMO"] != nil {
                renderBandDemo(to: out)
            } else {
                renderGlyph(quotes: quotes, to: out)
            }
        }
    }

    /// One synthetic VN equity per band, at a plausible price, so every colour is on screen together.
    @MainActor
    static func renderBandDemo(to path: String) {
        // Reference 50,000 with a ±7% HOSE band: ceiling 53,500, floor 46,500.
        let ref = 50_000.0, ceiling = 53_500.0, floor = 46_500.0
        let cases: [(String, Double)] = [
            ("CEIL", ceiling),   // trần   → purple
            ("UP",   51_000),    // tăng   → green
            ("REF",  ref),       // tham chiếu → yellow
            ("DOWN", 48_000),    // giảm   → red
            ("FLOOR", floor),    // sàn    → cyan
        ]
        let quotes = cases.map { name, price in
            Quote(symbol: name, market: .vietnam, price: price, reference: ref,
                  ceiling: ceiling, floor: floor, volume: nil, asOf: Date())
        }
        print(String(repeating: "─", count: 78))
        for q in quotes { print("  \(q.symbol) → \(q.band)") }
        renderGlyph(quotes: quotes, to: path, sorted: false)
    }

    @MainActor
    static func renderGlyph(quotes: [Quote], to path: String, sorted: Bool = true) {
        // The label's `isDark` is read off NSApp, which picks the glyph's neutral text colour — so the
        // shared application has to exist before the label is built.
        _ = NSApplication.shared

        let ordered = sorted ? quotes.sorted { $0.symbol < $1.symbol } : quotes
        // Through MenuBarLabel.make rather than by hand, so the probe renders the label the app would
        // render — including the dash row for a symbol with no quote.
        let label = MenuBarLabel.make(
            pinned: ordered.map { WatchedSymbol(symbol: $0.symbol, market: $0.market, pinnedToMenuBar: true) },
            quotes: Dictionary(uniqueKeysWithValues: ordered.map {
                ("\($0.market.rawValue):\($0.symbol)", $0)
            }),
            staleIDs: [],
            showChange: true,
            isDark: NSApp.isDarkAppearance
        )
        let image = MenuBarGlyph.image(for: label)

        // Draw onto a mid-grey backdrop at 2× so the light-mode text (which is near-black) is visible
        // in the file at all — a PNG of black-on-transparent looks empty in most viewers.
        let scale: CGFloat = 2
        let pad: CGFloat = 8
        let size = NSSize(width: (image.size.width + pad * 2) * scale,
                          height: (image.size.height + pad * 2) * scale)
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil,
                                         pixelsWide: Int(size.width), pixelsHigh: Int(size.height),
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                         isPlanar: false, colorSpaceName: .deviceRGB,
                                         bytesPerRow: 0, bitsPerPixel: 0) else { return }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSColor(white: 0.55, alpha: 1).setFill()
        NSRect(origin: .zero, size: size).fill()
        image.draw(in: NSRect(x: pad * scale, y: pad * scale,
                              width: image.size.width * scale, height: image.size.height * scale))
        NSGraphicsContext.restoreGraphicsState()

        guard let data = rep.representation(using: .png, properties: [:]) else { return }
        try? data.write(to: URL(fileURLWithPath: path))
        print(String(repeating: "─", count: 78))
        print("menu-bar glyph: \(Int(image.size.width))×\(Int(image.size.height))pt → \(path)")
    }
}
