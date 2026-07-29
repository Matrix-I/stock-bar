// QuoteTests.swift — the band classification and the change arithmetic.
//
// The band is where the Vietnamese colour convention is decided, and getting it wrong produces a green
// row where the board shows purple: still plausible, still wrong. The epsilon in particular is not
// recoverable from a single passing case — the tests below bracket it, so shrinking it to `==` or widening
// it to a percent both go red.

import Testing
import Foundation
@testable import StockBarCore

@Suite("Quote")
struct QuoteTests {

    /// A HOSE-shaped quote: reference 50,000 with the ±7% band it implies.
    private func vn(price: Double, reference: Double? = 50_000,
                    ceiling: Double? = 53_500, floor: Double? = 46_500) -> Quote {
        Quote(symbol: "VCB", market: .vietnam, price: price, reference: reference,
              ceiling: ceiling, floor: floor, volume: nil, asOf: Date())
    }

    // MARK: Bands

    @Test("A price at its ceiling is trần, not merely up")
    func ceilingBeatsUp() {
        // Arithmetically this is also "up" — a VN board still paints it purple, so ceiling has to win.
        #expect(vn(price: 53_500).band == .ceiling)
        #expect(vn(price: 46_500).band == .floor)
    }

    @Test("The ceiling test tolerates rounding, but only rounding")
    func ceilingEpsilon() {
        // The band limits arrive as independently rounded tick values, so `==` misses often enough to be
        // a visible bug. The tolerance is relative: max(ceiling, 1) * 1e-6, so ~0.0535 here.
        #expect(vn(price: 53_500.02).band == .ceiling)
        // Half a dong away is a real price below the ceiling, and must read as up rather than locked.
        #expect(vn(price: 53_500.5).band == .up)
    }

    @Test("Ordinary moves are classified by sign")
    func upDownUnchanged() {
        #expect(vn(price: 51_000).band == .up)
        #expect(vn(price: 48_000).band == .down)
        #expect(vn(price: 50_000).band == .unchanged)
    }

    @Test("With no usable reference there is no move to classify")
    func missingReference() {
        // nil and 0 both mean "the upstream didn't give us one". Treating 0 as a real reference would
        // divide by it and report an infinite percentage.
        #expect(vn(price: 51_000, reference: nil, ceiling: nil, floor: nil).band == .unchanged)
        #expect(vn(price: 51_000, reference: 0, ceiling: nil, floor: nil).band == .unchanged)
        #expect(vn(price: 51_000, reference: nil, ceiling: nil, floor: nil).change == nil)
        #expect(vn(price: 51_000, reference: 0, ceiling: nil, floor: nil).changePercent == nil)
    }

    @Test("A crypto quote has no band limits, so it only ever reads up, down or unchanged")
    func cryptoHasNoBand() {
        let q = Quote(symbol: "BTCUSDT", market: .crypto, price: 64_134, reference: 63_000,
                      ceiling: nil, floor: nil, volume: nil, asOf: Date())
        #expect(q.band == .up)
    }

    // MARK: Change

    @Test("Change and percentage are measured against the reference")
    func changeArithmetic() {
        let q = vn(price: 51_000)
        #expect(q.change == 1_000)
        #expect(q.changePercent == 2)
    }

    // MARK: Arrows

    @Test("Each band has its own arrow, and the locked ones are doubled")
    func arrows() {
        // Doubled glyphs for ceiling/floor so the two locked states stay distinguishable for anyone who
        // can't rely on the colour.
        #expect(PriceBand.ceiling.arrow == "⇑")
        #expect(PriceBand.floor.arrow == "⇓")
        #expect(PriceBand.up.arrow == "▲")
        #expect(PriceBand.down.arrow == "▼")
        #expect(PriceBand.unchanged.arrow == "=")
        let arrows = Set([PriceBand.ceiling, .floor, .up, .down, .unchanged].map(\.arrow))
        #expect(arrows.count == 5)
    }

    @Test("A quote knows whether it is an index")
    func isIndex() {
        #expect(Quote(symbol: "VNINDEX", market: .vietnam, price: 1, reference: nil, ceiling: nil,
                      floor: nil, volume: nil, asOf: Date()).isIndex)
        #expect(vn(price: 1).isIndex == false)
    }
}
