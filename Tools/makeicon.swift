// makeicon.swift — renders AppIcon.icns from BrandMark's geometry.
//
//   ./Tools/makeicon.sh          # writes AppIcon.icns in the repo root
//
// The icon is generated rather than drawn in an editor and committed as an opaque .icns for the same
// reason everything else here is code: it can be re-derived. `Tools/makeicon.sh` compiles this file
// together with Sources/View/Design/BrandMark.swift, so the mark on the icon is the same five points the
// menu bar strokes when nothing is pinned, and a change to the shape reaches both.
//
// Every size is rendered from the path at its own pixel size instead of downscaling 1024 ten times. That
// is the whole reason to do this in code: at 16px a scaled-down copy of the large artwork is a grey
// smudge, so the small tiers get a tighter margin, a proportionally heavier stroke, and none of the
// decoration that only reads when it is large.

import AppKit

@main
struct MakeIcon {

    /// The tiers `iconutil` expects. 32, 256 and 512 each appear twice — once as a size and once as
    /// another size's @2x — and are rendered twice rather than symlinked, because the recipe is chosen by
    /// pixel size and both copies must be the same pixels.
    static let tiers: [(name: String, px: Int)] = [
        ("icon_16x16", 16), ("icon_16x16@2x", 32),
        ("icon_32x32", 32), ("icon_32x32@2x", 64),
        ("icon_128x128", 128), ("icon_128x128@2x", 256),
        ("icon_256x256", 256), ("icon_256x256@2x", 512),
        ("icon_512x512", 512), ("icon_512x512@2x", 1024),
    ]

    static func main() throws {
        let out = URL(fileURLWithPath: CommandLine.arguments.count > 1
                      ? CommandLine.arguments[1] : ".build/AppIcon.iconset")
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

        for tier in tiers {
            let png = try render(px: tier.px)
            try png.write(to: out.appendingPathComponent("\(tier.name).png"))
            print("   \(tier.name).png  \(tier.px)×\(tier.px)  \(png.count) bytes")
        }
    }

    // MARK: - Palette
    //
    // Resolved from the semantic colours the app itself uses, not picked by eye: the rise is painted in
    // the very green BandStyle paints an up price with, so the icon cannot end up a different green from
    // the thing it depicts. `.icns` is static, so the dark-appearance variant is the one taken — the
    // artwork is dark, and that is the pair Apple tuned for a dark backdrop.

    static let rise: CGColor = {
        var resolved = NSColor.systemGreen
        NSAppearance(named: .darkAqua)?.performAsCurrentDrawingAppearance {
            resolved = NSColor.systemGreen.usingColorSpace(.sRGB) ?? resolved
        }
        return resolved.cgColor
    }()

    /// Graphite with a hint of blue, lighter at the top: the panel's own family, so the icon in the Dock
    /// and the popover under the menu bar look like the same application.
    static let backdropTop = CGColor(srgbRed: 0.17, green: 0.19, blue: 0.24, alpha: 1)
    static let backdropBottom = CGColor(srgbRed: 0.07, green: 0.08, blue: 0.11, alpha: 1)
    /// An inner hairline. Apple's own icons carry one; without it a dark icon on a dark Dock loses its
    /// silhouette entirely.
    static let rim = CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.12)
    static let shadow = CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.28)

    // MARK: - Drawing

    static func render(px: Int) throws -> Data {
        let size = CGFloat(px)
        // Below this the decoration stops helping and starts filling in: a 16px tile has no room for a
        // shadow, and the margin and the mark have to be re-proportioned to leave the line any pixels.
        let small = px <= 32

        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px,
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                         isPlanar: false, colorSpaceName: .deviceRGB,
                                         bytesPerRow: 0, bitsPerPixel: 0),
              let ctx = NSGraphicsContext(bitmapImageRep: rep) else {
            throw Failure("could not open a \(px)×\(px) bitmap")
        }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = ctx
        defer { NSGraphicsContext.restoreGraphicsState() }
        let cg = ctx.cgContext

        // A macOS app icon is artwork inset in a transparent canvas rather than a full-bleed tile — the
        // margin is where the shadow goes and what keeps neighbouring Dock icons from touching. Small
        // tiers give some of it back, because at 16px a tenth of the canvas is a pixel and a half of
        // nothing.
        let margin = size * (small ? 0.06 : 0.098)
        let art = CGRect(x: margin, y: margin, width: size - margin * 2, height: size - margin * 2)
        let squircle = BrandMark.squircle(in: art)

        if !small {
            cg.setShadow(offset: CGSize(width: 0, height: -size * 0.010), blur: size * 0.024,
                         color: shadow)
        }
        cg.addPath(squircle)
        cg.setFillColor(backdropBottom)
        cg.fillPath()
        cg.setShadow(offset: .zero, blur: 0, color: nil)

        cg.saveGState()
        cg.addPath(squircle)
        cg.clip()
        if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                     colors: [backdropTop, backdropBottom] as CFArray,
                                     locations: [0, 1]) {
            cg.drawLinearGradient(gradient,
                                  start: CGPoint(x: art.midX, y: art.maxY),
                                  end: CGPoint(x: art.midX, y: art.minY),
                                  options: [])
        }
        cg.restoreGState()

        // The mark's own box, centred in the squircle. Bigger in the small tiers: the margin an icon
        // needs is a constant of the canvas, but legibility is a constant of the mark.
        let box = art.width * (small ? 0.68 : 0.58)
        let markRect = CGRect(x: art.midX - box / 2, y: art.midY - box / 2, width: box, height: box)
        let lineWidth = BrandMark.lineWidth(for: box)

        cg.setStrokeColor(rise)
        cg.setLineWidth(lineWidth)
        cg.setLineCap(.round)
        cg.setLineJoin(.round)
        cg.addPath(BrandMark.line(in: markRect, lineWidth: lineWidth))
        cg.strokePath()

        // Drawn last and inset by half its width so it lands just inside the edge instead of straddling
        // it, where antialiasing would spill a light line onto the transparent canvas.
        let rimWidth = max(size * 0.0025, 0.5)
        cg.setStrokeColor(rim)
        cg.setLineWidth(rimWidth)
        cg.addPath(BrandMark.squircle(in: art.insetBy(dx: rimWidth / 2, dy: rimWidth / 2)))
        cg.strokePath()

        guard let png = rep.representation(using: .png, properties: [:]) else {
            throw Failure("could not encode the \(px)×\(px) tier as PNG")
        }
        return png
    }

    struct Failure: Error, CustomStringConvertible {
        let description: String
        init(_ description: String) { self.description = description }
    }
}
