// DetailCardLayoutTests.swift — the three tiers the floating hover card is placed by.
//
// Worth testing because most of them are unreachable by hand: the flip needs a row at the bottom of a list
// that is itself as tall as the screen allows, the spill needs a watchlist shorter than the card, and the
// clamp needs a window barely taller than the card. Those are exactly the cases where getting it wrong puts
// a card over the price it is describing, or half outside the window.

import Testing
import Foundation
@testable import StockBarCore

@Suite("DetailCardLayout")
struct DetailCardLayoutTests {

    // Roughly the real numbers: a panel the size the app opens at, a list region between a measured header
    // and a measured footer, and a card the height a Vietnamese equity's seven label/value rows come to.
    private let panel = DetailCardLayout.Span(top: 0, bottom: 500)
    private let list = DetailCardLayout.Span(top: 55, bottom: 300)
    private let card: CGFloat = 100
    private let gap: CGFloat = 6
    private let margin: CGFloat = 4

    private func top(rowTop: CGFloat, rowBottom: CGFloat, card: CGFloat? = nil,
                     list: DetailCardLayout.Span? = nil,
                     panel: DetailCardLayout.Span? = nil) -> CGFloat {
        DetailCardLayout.top(rowTop: rowTop, rowBottom: rowBottom,
                             cardHeight: card ?? self.card,
                             list: list ?? self.list, panel: panel ?? self.panel,
                             gap: gap, margin: margin)
    }

    @Test("A row with room under it gets the card under it")
    func below() {
        #expect(top(rowTop: 100, rowBottom: 140) == 146)
    }

    @Test("The card goes below while it fits by a single point, and flips as soon as it doesn't")
    func theBoundary() {
        // A list deep enough that both sides of these rows have room, so the switch is a pure question of
        // preference rather than of what is left. 290 + gap + card + margin == 400, its bottom edge.
        //
        // Spelled with the CGFloat properties rather than as `290 + 6`: an expectation written out of
        // integer literals alone is typed Int, and `#expect` then compiles a CGFloat-against-Int comparison
        // that is simply always false. Using the same tokens the code uses also says which number is which.
        let deep = DetailCardLayout.Span(top: 55, bottom: 400)
        #expect(top(rowTop: 240, rowBottom: 290, list: deep) == 290 + gap)
        // One point lower and below would hang past the list, so the card goes above the row instead.
        #expect(top(rowTop: 241, rowBottom: 291, list: deep) == 241 - gap - card)
    }

    @Test("The bottom row of the list flips its card above itself rather than over the footer")
    func flipsWithinTheList() {
        let y = top(rowTop: 250, rowBottom: 300)
        #expect(y == 144)
        // Above the row, clear of the header, and nowhere near the footer below.
        #expect(y + card < 250)
        #expect(y >= list.top + margin)
    }

    @Test("A list too short for the card spills over the footer instead of over the row it describes")
    func spillsOverTheChrome() {
        // Two watched symbols and a seven-row card: the whole list is shallower than the card is tall, so
        // neither side of the row has the room. Covering the settings block for as long as the pointer
        // rests there is the lesser harm — covering the price being read would make the card pointless.
        let shortList = DetailCardLayout.Span(top: 55, bottom: 155)
        let y = top(rowTop: 105, rowBottom: 155, list: shortList)
        #expect(y == 161)
        #expect(y >= 155)
    }

    @Test("With no room even in the panel the card stays inside the window")
    func clampedInside() {
        // A 120pt window: below would end at 190 and above would start at -66.
        let tiny = DetailCardLayout.Span(top: 0, bottom: 120)
        let y = top(rowTop: 40, rowBottom: 80, list: tiny, panel: tiny)
        #expect(y == 16)
        #expect(y + card == 120 - margin)
    }

    @Test("A card taller than the window is pinned to the top margin rather than centred out of view")
    func tallerThanTheWindow() {
        let tiny = DetailCardLayout.Span(top: 0, bottom: 80)
        #expect(top(rowTop: 20, rowBottom: 60, list: tiny, panel: tiny) == margin)
    }

    @Test("Before the card has been measured it still gets a position, which is why the caller hides it")
    func unmeasured() {
        // A card of no height fits wherever it is put, so the answer is the position for a card that isn't
        // there yet. DetailCardOverlay keeps it invisible until the measurement lands rather than showing a
        // full-size card at a position computed for nothing.
        #expect(top(rowTop: 100, rowBottom: 140, card: 0) == 146)
    }
}
