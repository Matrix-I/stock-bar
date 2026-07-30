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

    // MARK: The day boundary

    /// An instant in ICT, the only zone a session's day is measured in. 2026-07-29 is a Wednesday,
    /// 2026-07-31 a Friday, 2026-08-01 a Saturday and 2026-08-03 a Monday.
    private func ict(_ month: Int, _ day: Int, _ hour: Int, _ minute: Int) -> Date {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = MarketHours.ict
        return cal.date(from: DateComponents(year: 2026, month: month, day: day,
                                             hour: hour, minute: minute))!
    }

    /// A HOSE quote that closed at 51,000 against a reference of 50,000 — up 2% — read at `asOf`.
    private func closed(at asOf: Date) -> Quote {
        Quote(symbol: "VCB", market: .vietnam, price: 51_000, reference: 50_000,
              ceiling: 53_500, floor: 46_500, volume: 542_780, asOf: asOf)
    }

    @Test("Its own session's evening leaves the quote exactly as fetched")
    func eveningOfTheSameDay() {
        // 15:00 to midnight is still the day that produced the number, so the close keeps reporting the move
        // it made. A reset that fired at the close would blank the day's result while people are reading it.
        let q = closed(at: ict(7, 29, 14, 59)).rebasedForPendingSession(at: ict(7, 29, 22, 0))
        #expect(q.change == 1_000)
        #expect(q.band == .up)
        #expect(q.ceiling == 53_500)
    }

    @Test("Past midnight the quote is rebased onto its own close and reads flat")
    func afterMidnightIsFlat() {
        let q = closed(at: ict(7, 29, 14, 59)).rebasedForPendingSession(at: ict(7, 30, 0, 30))
        #expect(q.change == 0)
        #expect(q.changePercent == 0)
        #expect(q.band == .unchanged)
        // The price is the last one that exists and stays; the reference becomes it, which is the number
        // HOSE itself will publish for the coming session.
        #expect(q.price == 51_000)
        #expect(q.reference == 51_000)
        // asOf and volume survive, so the panel can still say which session this reading came from.
        #expect(q.asOf == ict(7, 29, 14, 59))
        #expect(q.volume == 542_780)
    }

    @Test("A stock that closed limit-up is not still purple overnight")
    func ceilingDoesNotSurviveTheRollover() {
        // band reads ceiling/floor before it looks at the sign, so a ±7% band left over from the finished
        // session would paint trần beside a change of zero. The limits are dropped for exactly this reason.
        let locked = Quote(symbol: "VCB", market: .vietnam, price: 53_500, reference: 50_000,
                           ceiling: 53_500, floor: 46_500, volume: nil, asOf: ict(7, 29, 14, 59))
        #expect(locked.band == .ceiling)
        let next = locked.rebasedForPendingSession(at: ict(7, 30, 0, 30))
        #expect(next.band == .unchanged)
        #expect(next.ceiling == nil)
        #expect(next.floor == nil)
    }

    @Test("Friday's move is not still on screen on Saturday, or on Monday morning")
    func acrossTheWeekend() {
        let friday = closed(at: ict(7, 31, 14, 59))
        #expect(friday.rebasedForPendingSession(at: ict(8, 1, 10, 0)).change == 0)   // Saturday
        #expect(friday.rebasedForPendingSession(at: ict(8, 2, 20, 0)).change == 0)   // Sunday
        // Monday 09:05: the board is in its opening auction with no matched price, so this Friday reading is
        // still the newest one there is. Testing the clock instead of the reading would have decided the
        // session had started and put Friday's +2% back for the ten minutes until a real quote lands.
        #expect(friday.rebasedForPendingSession(at: ict(8, 3, 9, 5)).change == 0)
        // And once Monday's own quote arrives it is left alone.
        #expect(closed(at: ict(8, 3, 9, 20)).rebasedForPendingSession(at: ict(8, 3, 9, 20)).change == 1_000)
    }

    @Test("A reading taken before the open stays flat after the bell")
    func preOpenReadingStaysFlat() {
        // At 08:00 the board is still serving the finished session's reference, so a quote fetched then says
        // nothing about today however late it is read. This is the case that pins the test to the reading's
        // own timestamp rather than the clock: asking `now` would un-flatten it the moment 09:00 passed,
        // with no new data behind the change it went back to showing.
        #expect(closed(at: ict(8, 3, 8, 0)).rebasedForPendingSession(at: ict(8, 3, 10, 0)).change == 0)
    }

    @Test("Crypto has no session to wait for, so midnight changes nothing")
    func cryptoIgnoresTheDayBoundary() {
        // Binance quotes against a rolling 24-hour window, not a session. Flattening it at ICT midnight
        // would erase a move that is still happening — and pick an arbitrary zone to erase it in.
        let btc = Quote(symbol: "BTCUSDT", market: .crypto, price: 64_134, reference: 63_000,
                        ceiling: nil, floor: nil, volume: nil, asOf: ict(7, 29, 23, 59))
        #expect(btc.rebasedForPendingSession(at: ict(7, 30, 0, 1)).change == 1_134)
        #expect(btc.rebasedForPendingSession(at: ict(8, 2, 3, 0)).band == .up)      // Sunday, too
    }

    @Test("A quote knows whether it is an index")
    func isIndex() {
        #expect(Quote(symbol: "VNINDEX", market: .vietnam, price: 1, reference: nil, ceiling: nil,
                      floor: nil, volume: nil, asOf: Date()).isIndex)
        #expect(vn(price: 1).isIndex == false)
    }
}
