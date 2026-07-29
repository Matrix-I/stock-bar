// Sparkline.swift — a minimal line chart of recent closes.
//
// Deliberately axis-less and label-less: there is room for the shape of the last session and nothing
// else, and a shape is all this needs to answer "which way has it been going".

import SwiftUI

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
                let points = points(in: geo.size)
                ZStack {
                    area(through: points, in: geo.size).fill(color.opacity(Theme.Opacity.sparklineArea))
                    Path { $0.addLines(points) }
                        .stroke(color, style: StrokeStyle(lineWidth: Theme.Chart.lineWidth,
                                                          lineCap: .round, lineJoin: .round))
                }
            }
        }
    }

    private func points(in size: CGSize) -> [CGPoint] {
        let lo = values.min() ?? 0
        let hi = values.max() ?? 1
        // A dead-flat series (a stock that hasn't moved all session) would divide by zero on the
        // normalisation below; pin it to the vertical centre instead.
        let span = hi - lo
        let inset = Theme.Chart.inset
        return values.enumerated().map { i, v in
            let x = size.width * Double(i) / Double(values.count - 1)
            let norm = span > 0 ? (v - lo) / span : 0.5
            return CGPoint(x: x, y: inset + (size.height - inset * 2) * (1 - norm))
        }
    }

    /// A faint fill under the line gives the eye a baseline to read the slope against without spending
    /// pixels on an axis: the same points, closed down to the bottom edge.
    private func area(through points: [CGPoint], in size: CGSize) -> Path {
        Path { p in
            p.addLines(points)
            p.addLine(to: CGPoint(x: size.width, y: size.height))
            p.addLine(to: CGPoint(x: 0, y: size.height))
            p.closeSubpath()
        }
    }
}
