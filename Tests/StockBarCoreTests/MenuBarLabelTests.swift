// MenuBarLabelTests.swift — what the menu bar says, and when the glyph has to be redrawn.
//
// The equality is the interesting half. The glyph is rebuilt ~1 Hz and is expensive, so AppDelegate skips
// the ticks where the label is unchanged — which means anything that affects the drawing must affect the
// value. This replaced a hand-assembled cache-key string, where the failure mode was a menu bar that
// silently stopped updating because one field had been left out of the key.

import Testing
import Foundation
@testable import StockBarCore

@Suite("MenuBarLabel")
struct MenuBarLabelTests {

    private let vnindex = WatchedSymbol(symbol: "VNINDEX", market: .vietnam, pinnedToMenuBar: true)
    private let btc = WatchedSymbol(symbol: "BTCUSDT", market: .crypto, pinnedToMenuBar: true)

    private func quote(_ entry: WatchedSymbol, price: Double, reference: Double?) -> (String, Quote) {
        (entry.id, Quote(symbol: entry.symbol, market: entry.market, price: price, reference: reference,
                         ceiling: nil, floor: nil, volume: nil, asOf: Date()))
    }

    private func label(pinned: [WatchedSymbol], quotes: [String: Quote],
                       staleIDs: Set<String> = [], showChange: Bool = true,
                       isDark: Bool = true) -> MenuBarLabel {
        MenuBarLabel.make(pinned: pinned, quotes: quotes, staleIDs: staleIDs,
                          showChange: showChange, isDark: isDark)
    }

    @Test("A quoted symbol carries its alias, its price and its percentage")
    func quotedRow() {
        let l = label(pinned: [vnindex],
                      quotes: Dictionary(uniqueKeysWithValues: [quote(vnindex, price: 1704.68, reference: 1680)]))
        #expect(l.entries.count == 1)
        #expect(l.entries[0].label == "VNI")             // the ticker is too long for a menu bar
        #expect(l.entries[0].price == "1,704.68")        // index precision, same as the popover's
        #expect(l.entries[0].change == "+1.47%")
        #expect(l.entries[0].band == .up)
        #expect(l.entries[0].stale == false)
    }

    @Test("A pinned symbol with no quote still gets a row")
    func missingQuoteBecomesADash() {
        // Skipping it meant a symbol that failed to fetch vanished from the menu bar completely, which is
        // indistinguishable from it never having been pinned — the user blames the pin, not the feed.
        let l = label(pinned: [vnindex, btc], quotes: [:])
        #expect(l.entries.count == 2)
        #expect(l.entries.allSatisfy { $0.price == "—" })
        #expect(l.entries.allSatisfy { $0.change == nil })
        #expect(l.entries.allSatisfy { $0.band == nil })   // neither up nor down would be honest
        #expect(l.entries.allSatisfy { $0.stale })
    }

    @Test("Hiding the percentage drops it from the label but keeps the price")
    func showChangeToggle() {
        let quotes = Dictionary(uniqueKeysWithValues: [quote(btc, price: 64_134, reference: 63_000)])
        let shown = label(pinned: [btc], quotes: quotes, showChange: true)
        let hidden = label(pinned: [btc], quotes: quotes, showChange: false)
        #expect(shown.entries[0].change != nil)
        #expect(hidden.entries[0].change == nil)
        #expect(hidden.entries[0].price == shown.entries[0].price)
        // Must not compare equal, or toggling the setting would leave the old glyph on screen.
        #expect(shown != hidden)
    }

    @Test("A theme switch produces a different label")
    func appearanceIsPartOfTheValue() {
        // A coloured image cannot be a template, so the glyph bakes its own neutral text colour and would
        // otherwise not re-tint when the system flips to dark mode.
        let quotes = Dictionary(uniqueKeysWithValues: [quote(btc, price: 64_134, reference: 63_000)])
        #expect(label(pinned: [btc], quotes: quotes, isDark: true)
                != label(pinned: [btc], quotes: quotes, isDark: false))
    }

    @Test("Staleness is part of the value, because it dims what is drawn")
    func stalenessIsPartOfTheValue() {
        let quotes = Dictionary(uniqueKeysWithValues: [quote(btc, price: 64_134, reference: 63_000)])
        let fresh = label(pinned: [btc], quotes: quotes)
        let stale = label(pinned: [btc], quotes: quotes, staleIDs: [btc.id])
        #expect(stale.entries[0].stale)
        #expect(fresh != stale)
    }

    @Test("The same inputs produce an equal label, so an unchanged tick costs no redraw")
    func equalInputsAreEqual() {
        let quotes = Dictionary(uniqueKeysWithValues: [quote(btc, price: 64_134, reference: 63_000)])
        #expect(label(pinned: [btc], quotes: quotes) == label(pinned: [btc], quotes: quotes))
    }

    @Test("Reordering the pinned rows changes the label")
    func orderMatters() {
        let quotes = Dictionary(uniqueKeysWithValues: [
            quote(vnindex, price: 1704.68, reference: 1680),
            quote(btc, price: 64_134, reference: 63_000),
        ])
        #expect(label(pinned: [vnindex, btc], quotes: quotes)
                != label(pinned: [btc, vnindex], quotes: quotes))
    }

    @Test("VoiceOver gets the tickers spelled out, and something to say when there is nothing")
    func accessibility() {
        let quotes = Dictionary(uniqueKeysWithValues: [quote(btc, price: 64_134, reference: 63_000)])
        #expect(label(pinned: [btc], quotes: quotes).accessibilityDescription == "BTC 64,134.00, +1.80%")
        #expect(label(pinned: [], quotes: [:]).accessibilityDescription == "StockBar, nothing pinned")
    }

    @Test("Nothing pinned is the mark; a pinned symbol without a quote is still text")
    func nothingPinnedIsNotTheSameAsNoData() {
        // The menu bar draws the app's mark instead of a label when this is true, so the failure mode is a
        // symbol the user pinned vanishing behind an icon: the app would look idle rather than broken, and
        // the one row that says "pinned, no data" would be the row that got hidden.
        #expect(label(pinned: [], quotes: [:]).hasNothingPinned)
        #expect(label(pinned: [btc], quotes: [:]).hasNothingPinned == false)
    }

    @Test("Four or fewer pinned rows never rotate, whatever the clock says")
    func windowIsStaticAtOrUnderTheCap() {
        // The common case has to keep today's behaviour exactly: a menu bar that reshuffles two pinned
        // symbols every eight seconds is churn with no information in it, and every offset the wall clock
        // can produce must land on the same window or the 1 Hz equality gate stops saving the redraws.
        let four = ["VNINDEX", "VCB", "BTCUSDT", "GOLD"].map {
            WatchedSymbol(symbol: $0, market: .vietnam, pinnedToMenuBar: true)
        }
        for offset in [0, 1, 3, 17, 9_999] {
            #expect(MenuBarLabel.visibleWindow(of: four, at: offset) == four)
        }
        #expect(MenuBarLabel.visibleWindow(of: Array(four.prefix(2)), at: 5) == Array(four.prefix(2)))
        #expect(MenuBarLabel.visibleWindow(of: [], at: 3).isEmpty)
    }

    @Test("Past the cap the window advances one symbol per step and wraps")
    func windowRotates() {
        let six = ["A1", "B2", "C3", "D4", "E5", "F6"].map {
            WatchedSymbol(symbol: $0, market: .vietnam, pinnedToMenuBar: true)
        }
        let names = { (offset: Int) in
            MenuBarLabel.visibleWindow(of: six, at: offset).map(\.symbol)
        }
        // One step, one symbol: the leftmost drops, the next joins on the right. Advancing by the whole
        // window instead would blink every symbol out after one step — each must survive four.
        #expect(names(0) == ["A1", "B2", "C3", "D4"])
        #expect(names(1) == ["B2", "C3", "D4", "E5"])
        // The wrap, which is where an off-by-one lives if one lives anywhere: the window reaching the end
        // of the list continues from its front rather than shrinking or crashing.
        #expect(names(4) == ["E5", "F6", "A1", "B2"])
        // A full cycle returns home, so the offset can grow without bound — it is a clock, not an index.
        #expect(names(6) == names(0))
        #expect(names(9_999 % 6) == names(9_999))
        // Negative-safe: a caller counting steps from an epoch it hasn't reached yet must not trap.
        #expect(names(-1) == ["F6", "A1", "B2", "C3"])
    }
}
