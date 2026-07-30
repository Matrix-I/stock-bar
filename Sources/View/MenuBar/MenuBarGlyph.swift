// MenuBarGlyph.swift — bakes a MenuBarLabel into a single NSImage.
//
// Why an image rather than NSStatusItem's `title` or a SwiftUI MenuBarExtra label: the label has to be
// MULTI-COLOURED (a green VN-Index next to a red BTC, and purple/cyan for a ceiling/floor lock). A
// template image renders monochrome — the system throws the colours away and tints by appearance — and
// a plain `title` string takes one colour for the whole run. Drawing an NSAttributedString into a
// non-template NSImage is the only route that keeps per-symbol colour.
//
// The cost of opting out of template rendering is that the system no longer auto-tints for light/dark, so
// the neutral parts (the ticker, the separator) are drawn in a colour taken from `label.isDark` — which is
// part of the label's value precisely so a theme switch produces a different label and a rebuilt image.
//
// The empty state is the exception and is drawn as a real template: with nothing pinned there are no band
// colours to keep, so there is nothing left to pay for.
//
// Sizes, weights and alphas are in MenuBarStyle; what to say is in Core/MenuBarLabel.swift. This file
// only draws.

import AppKit

enum MenuBarGlyph {

    @MainActor
    static func image(for label: MenuBarLabel) -> NSImage {
        if label.hasNothingPinned { return mark() }
        let neutral = MenuBarStyle.neutral(isDark: label.isDark)

        let line = attributedLine(label.entries, neutral: neutral)

        // Width comes from the measured string so the item hugs its content instead of reserving space
        // for a hypothetical maximum.
        let size = line.size()
        let h = MenuBarStyle.height
        let img = NSImage(size: NSSize(width: max(ceil(size.width), 1), height: h), flipped: false) { _ in
            // Non-flipped space (origin bottom-left). The +0.5 nudge centres the cap-height optically —
            // NSAttributedString's reported height includes descender space the digits here never use, so
            // a pure arithmetic centre sits a hair low against the neighbouring system items.
            line.draw(at: NSPoint(x: 0, y: (h - ceil(size.height)) / 2 + 0.5))
            return true
        }
        // MUST be false: a template image would discard every colour set above, which is the entire point
        // of baking the label ourselves.
        img.isTemplate = false
        return img
    }

    /// The whole line as one attributed string: each ticker in the adaptive neutral colour, its price and
    /// change in the band colour, entries separated by two spaces.
    private static func attributedLine(_ entries: [MenuBarEntry], neutral: NSColor) -> NSAttributedString {
        let line = NSMutableAttributedString()
        for (i, e) in entries.enumerated() {
            if i > 0 {
                line.append(NSAttributedString(string: MenuBarStyle.separator,
                                               attributes: [.font: MenuBarStyle.priceFont]))
            }
            let alpha: CGFloat = e.stale ? MenuBarStyle.staleAlpha : 1.0
            let tint = e.band.map { BandStyle.nsColor($0, market: e.market) } ?? BandStyle.noQuoteNSColor

            line.append(NSAttributedString(string: e.label + " ", attributes: [
                .font: MenuBarStyle.tickerFont,
                .foregroundColor: neutral.withAlphaComponent(alpha * MenuBarStyle.tickerAlpha),
            ]))
            line.append(NSAttributedString(string: e.price, attributes: [
                .font: MenuBarStyle.priceFont,
                .foregroundColor: tint.withAlphaComponent(alpha),
            ]))
            if let change = e.change {
                line.append(NSAttributedString(string: " " + change, attributes: [
                    .font: MenuBarStyle.priceFont,
                    .foregroundColor: tint.withAlphaComponent(alpha),
                ]))
            }
        }
        return line
    }

    /// Shown when nothing is pinned. Something visible is required either way — a zero-width status item
    /// is indistinguishable from a crash — and this used to be "— —", which said nothing about whose item
    /// it was. The state is fixed by pinning a symbol, and the user can only think to do that if they
    /// recognise the item as StockBar's, so the app's own mark is the thing to draw.
    ///
    /// The one case in this file that IS a template image: with no prices there are no band colours to
    /// preserve, so handing the shape to the system buys back everything opting out of template rendering
    /// costs — it tints for the appearance on its own, and it inverts while the item is pressed, like the
    /// system's own glyphs beside it.
    @MainActor
    private static func mark() -> NSImage {
        let box = MenuBarStyle.markBox
        let width = BrandMark.lineWidth(for: box)
        let img = NSImage(size: NSSize(width: box, height: MenuBarStyle.height), flipped: false) { rect in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            let square = CGRect(x: rect.minX, y: rect.midY - box / 2, width: box, height: box)
            ctx.setLineWidth(width)
            ctx.setLineCap(.round)
            ctx.setLineJoin(.round)
            // Any opaque colour would do: a template image keeps only the alpha channel.
            ctx.setStrokeColor(.black)
            ctx.addPath(BrandMark.line(in: square, lineWidth: width))
            ctx.strokePath()
            return true
        }
        img.isTemplate = true
        return img
    }
}
