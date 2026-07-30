// BrandMark.swift — the app's mark, as geometry: a rising price line with one pullback in it.
//
// It is a path rather than an exported PNG because it is drawn at two sizes that could hardly be
// further apart — 1024pt for AppIcon.icns, 14pt for the menu-bar item when nothing is pinned — and the
// two have to be the same shape. `Tools/makeicon.swift` compiles THIS file, so the icon on disk and the
// glyph in the menu bar are the same five points scaled differently; there is no second drawing of "the
// same" mark to drift the first time one of them is nudged.
//
// Nothing here knows a colour. The icon's palette belongs to the tool that renders it, and the menu-bar
// glyph is a template image whose colour the system chooses — see MenuBarGlyph.
//
// CoreGraphics only: the tool links it without SwiftUI, so this file must not reach for Theme or for any
// of the panel's types.

import CoreGraphics
import Foundation

enum BrandMark {

    /// The series, in a unit square with y pointing up. It fills its box rather than sitting politely in
    /// the middle of one — padding is the caller's decision, because the icon wants a lot and the menu
    /// bar has almost none to give.
    ///
    /// Deliberately NOT monotonic. Four ascending steps is the cellular-signal glyph, and 14pt of
    /// ascending steps in a menu bar is what it would be read as; the dip in the middle is what makes it
    /// a chart. It rises overall because this is the app's own mark and not a report on the market.
    ///
    /// Both ranges are centred on 0.5 — x spans 0.05…0.95 and y 0.16…0.84 — so a caller that centres the
    /// BOX gets an optically centred MARK. They were not, at first, and the 0.04 of slack put the glyph a
    /// visible half-point high against the system items beside it in the menu bar.
    static let series: [CGPoint] = [
        CGPoint(x: 0.05, y: 0.16),
        CGPoint(x: 0.29, y: 0.40),
        CGPoint(x: 0.51, y: 0.27),
        CGPoint(x: 0.73, y: 0.58),
        CGPoint(x: 0.95, y: 0.84),
    ]

    /// The line itself, to be stroked with round caps and joins at `lineWidth`.
    static func line(in rect: CGRect, lineWidth: CGFloat) -> CGPath {
        let path = CGMutablePath()
        path.addLines(between: points(in: rect, lineWidth: lineWidth))
        return path
    }

    // There is deliberately no area-fill path here, though the panel's sparklines have one. Closed down
    // to a baseline the shape has two hard vertical sides, and at icon scale those edges stop reading as
    // "under the line" and start reading as a translucent panel sitting on the artwork. The stroke alone
    // is also what survives 16 pixels.

    /// Optically sized rather than a single fraction: the same relative weight that looks right at 1024
    /// disappears at 14, where the stroke is competing with the system's own glyphs and has one pixel to
    /// do it in. The two tiers are what a menu bar and a Finder icon respectively need, not a curve worth
    /// interpolating.
    static func lineWidth(for box: CGFloat) -> CGFloat {
        box <= 48 ? box * 0.12 : box * 0.085
    }

    /// The rounded square the icon is drawn on: a superellipse, not `CGPath(roundedRect:)`. A circular
    /// corner next to macOS's own icons reads as slightly wrong in a way that is hard to name and easy to
    /// see; the exponent is the one Apple's continuous corner approximates.
    static func squircle(in rect: CGRect, exponent: CGFloat = 5, segments: Int = 360) -> CGPath {
        let path = CGMutablePath()
        let radii = CGSize(width: rect.width / 2, height: rect.height / 2)
        let power = 2 / exponent
        for i in 0..<segments {
            let t = 2 * CGFloat.pi * CGFloat(i) / CGFloat(segments)
            let point = CGPoint(
                x: rect.midX + copysign(pow(abs(cos(t)), power), cos(t)) * radii.width,
                y: rect.midY + copysign(pow(abs(sin(t)), power), sin(t)) * radii.height
            )
            if i == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        path.closeSubpath()
        return path
    }

    /// Inset by half the stroke, because round caps extend that far past the end points — without it the
    /// mark's first and last pixels are clipped by its own box, which at 14pt costs the whole top of the
    /// rise.
    private static func points(in rect: CGRect, lineWidth: CGFloat) -> [CGPoint] {
        let box = rect.insetBy(dx: lineWidth / 2, dy: lineWidth / 2)
        return series.map {
            CGPoint(x: box.minX + $0.x * box.width, y: box.minY + $0.y * box.height)
        }
    }
}
