// CardStyle.swift — the hover card's palette, and the one place in the panel that does NOT follow the
// system appearance.
//
// Everything else here is appearance-aware on purpose, so this needs its reason stated. The card is a light
// surface on both themes, deliberately: it is a thing lying ON the panel, and what makes that read is
// contrast against the panel rather than agreement with it. Built from `controlBackgroundColor` it inverted
// with the appearance — which is exactly wrong, because in dark mode that made it the panel's own colour and
// the card became a slightly-off rectangle rather than a card. In light mode nothing changes; the card
// already looked like this, and that is the look being kept.
//
// The values are literal rather than semantic for the same reason: a semantic colour is a promise to follow
// the appearance, and this file is the one that does not. They are only used together, as a set — the
// surface with its own two text weights, so contrast is decided here rather than at the call site.

import SwiftUI

enum CardStyle {
    /// Not pure white: a hair of grey keeps the values' black from vibrating against it, and separates the
    /// card from the white it sits on in light mode.
    static let surface = Color(white: 0.97)

    /// The label column reads as the quieter half of each pair.
    static let label = Color.black.opacity(0.55)
    static let value = Color.black.opacity(0.88)

    /// The edge, and the blur under it. Both are what stop a light rectangle on a dark panel from looking
    /// like a hole punched through to something behind.
    static let border = Color.black.opacity(0.16)
    static let shadow = Color.black.opacity(0.35)
}
