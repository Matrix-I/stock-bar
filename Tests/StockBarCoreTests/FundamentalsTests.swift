// FundamentalsTests.swift — the two valuation ratios and the book value recovered to compute one of them.
//
// The first test is the reason the type exists at all: the upstream hands over a ready-made P/E of 14.23
// for VCB, computed against a price the panel is not showing. Recomputing against the live price gives
// 12.97, which is what a reader dividing the two figures in front of them would get. If that test ever
// goes green on 14.23, the panel has started contradicting itself again.

import Testing
@testable import StockBarCore

@Suite("Fundamentals")
struct FundamentalsTests {

    // SSI's own figures for VCB, read live on 2026-07-30, against a board price of 54,600.
    private let ssiPE = 14.2279190180
    private let ssiEPS = 4210.0323964582
    private let ssiPB = 2.2295477291

    private var vcb: Fundamentals {
        Fundamentals(earningsPerShare: ssiEPS,
                     bookValuePerShare: Fundamentals.bookValuePerShare(pe: ssiPE, eps: ssiEPS, pb: ssiPB),
                     year: 2025)
    }

    @Test("The ratios follow the live price, not the vendor's snapshot")
    func ratiosTrackTheLivePrice() {
        let pe = vcb.priceEarnings(at: 54_600)
        #expect(pe != nil)
        // 54,600 ÷ 4,210.03 = 12.97 — and emphatically not the 14.23 the feed reported, which implies a
        // price of 59,884.
        #expect(PriceFormat.ratio(pe!) == "12.97")
        #expect(PriceFormat.ratio(pe!) != PriceFormat.ratio(ssiPE))
    }

    @Test("Book value is recovered exactly from the vendor's own three numbers")
    func bookValueRecovery() {
        let bvps = Fundamentals.bookValuePerShare(pe: ssiPE, eps: ssiEPS, pb: ssiPB)
        #expect(bvps != nil)
        // pe × eps comes out at 59,900.00 to the dong — a round tick, and a real VCB price from some
        // earlier session. That exactness is the evidence the feed's ratios are snapshot-based rather than
        // live, and it is what makes recovering the book value a rearrangement of its own numbers.
        #expect(abs(ssiPE * ssiEPS - 59_900) < 0.01)
        #expect(abs(bvps! - 26_866.44) < 0.01)
        // And feeding that price back in must reproduce the feed's own P/B, which is what makes the
        // recovery a rearrangement rather than an estimate.
        let atSnapshot = Fundamentals(earningsPerShare: ssiEPS, bookValuePerShare: bvps, year: 2025)
            .priceBook(at: ssiPE * ssiEPS)
        #expect(abs(atSnapshot! - ssiPB) < 1e-9)
    }

    @Test("A loss-maker's book value is still recoverable")
    func lossMakerBookValue() {
        // The feed reports a negative pe against the negative eps, so the product is the positive price it
        // used. Handling this without a special case is the reason the guard is on the product, not on eps.
        let bvps = Fundamentals.bookValuePerShare(pe: -8, eps: -500, pb: 1.5)
        #expect(bvps != nil)
        #expect(abs(bvps! - 2666.67) < 0.01)
    }

    @Test("A P/B of zero is the feed's way of saying not reported")
    func zeroPBIsNotAValue() {
        // The quarterly rows come back with every ratio at zero. Dividing by that would be an infinity.
        #expect(Fundamentals.bookValuePerShare(pe: 14, eps: 4000, pb: 0) == nil)
        #expect(Fundamentals.bookValuePerShare(pe: 0, eps: 4000, pb: 2) == nil)
        #expect(Fundamentals.bookValuePerShare(pe: nil, eps: 4000, pb: 2) == nil)
    }

    @Test("A loss-making company shows no P/E at all")
    func negativeEarningsHaveNoRatio() {
        // "P/E −8.4" is not a number anyone reads at a glance, so the row is omitted instead.
        let loss = Fundamentals(earningsPerShare: -500, bookValuePerShare: 2666, year: 2025)
        #expect(loss.priceEarnings(at: 4000) == nil)
        // The book is still positive and still worth showing.
        #expect(loss.priceBook(at: 4000) != nil)
    }

    @Test("Nothing to report yields no ratios and reads as empty")
    func emptyFundamentals() {
        #expect(Fundamentals.none.isEmpty)
        #expect(Fundamentals.none.priceEarnings(at: 54_600) == nil)
        #expect(Fundamentals.none.priceBook(at: 54_600) == nil)
        #expect(vcb.isEmpty == false)
    }

    @Test("A price of zero produces no ratio rather than a zero one")
    func zeroPriceIsNotAValuation() {
        // A stock that hasn't traded today reports lastPrice 0 upstream. Dividing it would print "0.00",
        // which reads as a real and extraordinary valuation.
        #expect(vcb.priceEarnings(at: 0) == nil)
        #expect(vcb.priceBook(at: 0) == nil)
    }
}
