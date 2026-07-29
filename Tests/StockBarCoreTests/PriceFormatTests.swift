// PriceFormatTests.swift — the formatters behind every number the app shows.
//
// Worth pinning because the failures here are silent: a wrong precision rule still prints a plausible
// price. Two of these rules exist because of bugs that shipped — the menu bar and the popover formatting
// independently, and a crypto price fixed at two decimals so the item stops jittering — and neither is
// recoverable from reading the output of a single case. The cases below are chosen to fail if a threshold
// moves or a fixed-decimal rule is relaxed, not to re-state the code.

import Testing
import Foundation
@testable import StockBarCore

@Suite("PriceFormat")
struct PriceFormatTests {

    // MARK: VND

    @Test("A VN equity price is grouped and whole above 1000")
    func vnEquityAboveThousand() {
        #expect(PriceFormat.vnPrice(62_400, isIndex: false) == "62,400")
        #expect(PriceFormat.vnPrice(62_400.4, isIndex: false) == "62,400")
    }

    @Test("A sub-1000 VND price keeps one decimal rather than collapsing to an integer")
    func vnPennyStock() {
        // The pair is the point: 999.5 must NOT round away, while 1000.6 must. A single case either side
        // of the threshold would pass against a formatter that always rounded, or one that never did.
        #expect(PriceFormat.vnPrice(999.5, isIndex: false) == "999.5")
        #expect(PriceFormat.vnPrice(1000.6, isIndex: false) == "1,001")
        // NumberFormatter rounds half-even, so an exact .5 tie above the threshold goes DOWN. Pinned
        // because it is surprising, not because it matters: a real VND tick is never a half dong.
        #expect(PriceFormat.vnPrice(1000.5, isIndex: false) == "1,000")
    }

    @Test("An index keeps exactly two decimals, the way every Vietnamese board prints it")
    func vnIndexTwoDecimals() {
        #expect(PriceFormat.vnPrice(1704.68, isIndex: true) == "1,704.68")
        // Fixed, not capped: a round index value still shows both places, so the menu-bar item does not
        // change width when it happens to land on a whole number.
        #expect(PriceFormat.vnPrice(1700, isIndex: true) == "1,700.00")
    }

    // MARK: Crypto

    @Test("A crypto price above 1 shows exactly two decimals")
    func cryptoTwoDecimals() {
        #expect(PriceFormat.cryptoPrice(64_134.01) == "64,134.01")
        #expect(PriceFormat.cryptoPrice(64_134) == "64,134.00")
    }

    @Test("Crypto precision scales with magnitude", arguments: [
        (0.5, "0.5"),           // 0.01..<1 → up to 4 places
        (0.1234, "0.1234"),
        (0.00004, "0.00004"),   // below 0.01 → up to 8, or a token reads "0.00"
    ])
    func cryptoSmallValues(value: Double, expected: String) {
        #expect(PriceFormat.cryptoPrice(value) == expected)
    }

    @Test("The market picks the formatter")
    func marketSelectsFormatter() {
        #expect(PriceFormat.price(62_400, market: .vietnam, isIndex: false) == "62,400")
        // The same number as a crypto price gains the cents a VND price drops.
        #expect(PriceFormat.price(62_400, market: .crypto, isIndex: false) == "62,400.00")
    }

    // MARK: Signs

    @Test("A negative percentage uses U+2212, not a hyphen")
    func percentUsesMinusSign() {
        // Load-bearing: with a hyphen the label visibly shifts every time a quote crosses zero, because a
        // hyphen is narrower than a plus in a monospaced-digit font.
        #expect(PriceFormat.percent(-1.1449) == "\u{2212}1.14%")
        #expect(PriceFormat.percent(-1.1449).contains("-") == false)
        #expect(PriceFormat.percent(0.8234) == "+0.82%")
    }

    @Test("An exactly unchanged percentage carries no sign at all")
    func percentUnchanged() {
        #expect(PriceFormat.percent(0) == "0.00%")
    }

    @Test("A change is formatted at the precision of the price it is a delta of")
    func changeMatchesPricePrecision() {
        #expect(PriceFormat.change(24.06, market: .vietnam, isIndex: true) == "+24.06")
        #expect(PriceFormat.change(-500, market: .vietnam, isIndex: false) == "\u{2212}500")
        #expect(PriceFormat.change(-12.5, market: .crypto, isIndex: false) == "\u{2212}12.50")
    }

    // MARK: Volume

    @Test("Volume is abbreviated by order of magnitude", arguments: [
        (999.0, "999"),
        (1000.0, "1k"),
        (834_000.0, "834k"),
        (12_400_000.0, "12.4M"),
        (1_500_000_000.0, "1.50B"),
    ])
    func volumeThresholds(shares: Double, expected: String) {
        #expect(PriceFormat.volume(shares) == expected)
    }

    @Test("A negative volume is clamped rather than printed")
    func volumeClamped() {
        // The upstreams have been seen to report a negative lot count on a symbol that hasn't traded.
        #expect(PriceFormat.volume(-5) == "0")
    }

    // MARK: As-of

    @Test("A fresh quote reads as just now, and a minute-old one in minutes")
    func asOfRecent() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        #expect(PriceFormat.asOf(now, now: now) == "just now")
        #expect(PriceFormat.asOf(now.addingTimeInterval(-44), now: now) == "just now")
        #expect(PriceFormat.asOf(now.addingTimeInterval(-45), now: now) == "0m ago")
        #expect(PriceFormat.asOf(now.addingTimeInterval(-600), now: now) == "10m ago")
    }

    @Test("Past an hour it switches to a clock time, because 73m ago is harder to reason about")
    func asOfFallsBackToClock() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let old = PriceFormat.asOf(now.addingTimeInterval(-3600), now: now)
        // Asserted as a shape, not a value: the formatter renders in the machine's own time zone, so a
        // literal here would only pass in whichever zone it was written in.
        #expect(old.contains("ago") == false)
        #expect(old.count == 5)
        #expect(old.dropFirst(2).first == ":")
    }
}
