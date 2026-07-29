// MenuBarGlyph.swift — bakes the menu-bar label into a single NSImage.
//
// Why an image rather than NSStatusItem's `title` or a SwiftUI MenuBarExtra label: the label has to be
// MULTI-COLOURED (a green VN-Index next to a red BTC, and purple/cyan for a ceiling/floor lock). A
// template image renders monochrome — the system throws the colours away and tints by appearance — and
// a plain `title` string takes one colour for the whole run. Drawing an NSAttributedString into a
// non-template NSImage is the only route that keeps per-symbol colour.
//
// The cost of opting out of template rendering is that the system no longer auto-tints for light/dark,
// so the neutral parts (the ticker label, the separator) are drawn in a colour read from the current
// appearance, and the caller folds that appearance into its cache key so the image is rebuilt on a
// theme switch. See AppDelegate.tickerGlyph.
//
// Monospaced digits are load-bearing, not cosmetic: with proportional digits the whole item changes
// width on almost every refresh, so every other menu-bar item to its left visibly jumps once a minute.

import AppKit

/// One symbol's worth of text for the menu bar, already resolved to strings and a colour.
struct MenuBarEntry {
    let label: String        // "VNI", "BTC"
    let price: String        // "1705", "64.4k"
    let change: String?      // "+1.43%" — nil when the change is unknown or the user hid it
    let color: NSColor       // band colour for price + change
    let stale: Bool          // draw dimmed: the quote is older than it should be
}

@MainActor
func tickerMenuBarImage(_ entries: [MenuBarEntry]) -> NSImage {
    let font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium)
    let labelFont = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .semibold)
    let isDark = NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
    let neutral: NSColor = isDark ? .white : .black

    guard !entries.isEmpty else { return placeholderImage(neutral: neutral) }

    // Build the whole line as one attributed string: the ticker in the adaptive neutral colour, the
    // price and change in the band colour, entries separated by two spaces.
    let line = NSMutableAttributedString()
    for (i, e) in entries.enumerated() {
        if i > 0 {
            line.append(NSAttributedString(string: "  ", attributes: [.font: font]))
        }
        // A stale row is drawn at reduced alpha rather than in a different hue: the colour still has to
        // mean up/down, so "old" has to be encoded on a different axis than colour.
        let alpha: CGFloat = e.stale ? 0.45 : 1.0
        line.append(NSAttributedString(string: e.label + " ", attributes: [
            .font: labelFont,
            .foregroundColor: neutral.withAlphaComponent(alpha * 0.75),
        ]))
        line.append(NSAttributedString(string: e.price, attributes: [
            .font: font,
            .foregroundColor: e.color.withAlphaComponent(alpha),
        ]))
        if let change = e.change {
            line.append(NSAttributedString(string: " " + change, attributes: [
                .font: font,
                .foregroundColor: e.color.withAlphaComponent(alpha),
            ]))
        }
    }

    // The menu bar gives us 22 points of height; 16 is the usable band for text once the standard
    // padding is accounted for. Width comes from the measured string so the item hugs its content
    // instead of reserving space for a hypothetical maximum.
    let size = line.size()
    let w = ceil(size.width)
    let h: CGFloat = 16

    let img = NSImage(size: NSSize(width: max(w, 1), height: h), flipped: false) { _ in
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

/// Shown before the first fetch lands, and whenever every pinned symbol is missing a quote. A visible
/// placeholder beats an empty item: a zero-width status item is indistinguishable from a crash.
@MainActor
private func placeholderImage(neutral: NSColor) -> NSImage {
    let text = "— —" as NSString
    let font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium)
    let attrs: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: neutral.withAlphaComponent(0.5),
    ]
    let size = text.size(withAttributes: attrs)
    let h: CGFloat = 16
    let img = NSImage(size: NSSize(width: ceil(size.width), height: h), flipped: false) { _ in
        text.draw(at: NSPoint(x: 0, y: (h - ceil(size.height)) / 2 + 0.5), withAttributes: attrs)
        return true
    }
    img.isTemplate = false
    return img
}
