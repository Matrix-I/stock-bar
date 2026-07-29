// MeasuredHeight.swift — lets a view report the height it actually laid out at.
//
// The panel needs this because a `ScrollView` reports no useful height of its own. The popover sizes
// itself to its SwiftUI content, and a ScrollView asked for its ideal height in that situation answers
// with roughly nothing — the panel collapses. So the content is measured un-scrolled first, and the
// ScrollView is then given a concrete height. The pinned header and footer are measured the same way,
// because the room left for the list is whatever they didn't take.
//
// This replaced three byte-for-byte identical PreferenceKey declarations. One mechanism, three call
// sites: `.measuringHeight(into: $listHeight)`.

import SwiftUI

/// A single key serves every region. `.onPreferenceChange` reads the value collected from the subtree of
/// the view it is attached to, so each region sees only its own measurement even though they all write
/// the same key — nothing reads it further up, where they would merge.
private struct HeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    /// `max`, not last-one-wins: the background GeometryReader emits a spurious 0 alongside the real
    /// height during an early layout pass, and letting that through leaves the measurement stuck at zero
    /// so the list never switches to the scrolling branch. Every pass recomputes from scratch, so a
    /// shrinking list is still tracked.
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

extension View {
    /// Write this view's laid-out height into `binding`.
    ///
    /// The `fixedSize` is part of the measurement, not decoration: without it the view accepts whatever
    /// height its parent offers and reports that back, which measures the container rather than the
    /// content.
    func measuringHeight(into binding: Binding<CGFloat>) -> some View {
        self
            .fixedSize(horizontal: false, vertical: true)
            .background(GeometryReader { proxy in
                Color.clear.preference(key: HeightKey.self, value: proxy.size.height)
            })
            .onPreferenceChange(HeightKey.self) { binding.wrappedValue = $0 }
    }
}
