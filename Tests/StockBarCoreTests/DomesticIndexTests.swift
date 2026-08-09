// DomesticIndexTests.swift — the domestic rows, and the arithmetic behind the one that is computed.
//
// The conversion tests carry the weight here. A gold gap has three constants in it — a Vietnamese weight,
// an international one and a currency — and getting any of them wrong still produces a seven-figure number
// that looks entirely reasonable on screen. There is no appearance to check it against, so the numbers
// below are pinned to figures measured from the live feeds on 2026-08-09.

import Testing
import Foundation
@testable import StockBarCore

@Suite("DomesticIndex")
struct DomesticIndexTests {

    @Test("The domestic rows are on the Vietnam market and carry their own venue")
    func listings() {
        #expect(Market.inferred(for: "SJC") == .vietnam)
        #expect(Market.inferred(for: "USDVND") == .vietnam)
        #expect(Market.inferred(for: "GOLDGAP") == .vietnam)
        // A HOSE ticker still says nothing about its market — the picker's choice has to stand.
        #expect(Market.inferred(for: "VCB") == nil)

        #expect(venueLabel("SJC") == "PNJ")          // whose quote it is, not what the bar is called
        #expect(venueLabel("USDVND") == "VCB")
        #expect(venueLabel("GOLDGAP") == "SJC − spot")
        #expect(venueLabel("VCB") == "HOSE")         // unchanged by any of this
        #expect(venueLabel("VNINDEX") == "Index")
    }

    @Test("Aliases resolve, and the spellings a listed company already owns are not among them")
    func aliases() {
        #expect(Ticker.canonical("vangsjc") == "SJC")
        #expect(Ticker.canonical(" goldsjc ") == "SJC")
        #expect(Ticker.canonical("tygia") == "USDVND")
        #expect(Ticker.canonical("gap") == "GOLDGAP")
        // USD is a live UPCOM ticker and VND is VNDirect on HOSE. Claiming either would file a real company
        // under a gold feed, which is the collision this table was checked against the board to avoid — and
        // it fails silently, because the row would simply show somebody else's price.
        #expect(Ticker.canonical("USD") == "USD")
        #expect(Ticker.canonical("VND") == "VND")
        #expect(DomesticIndex.listing(for: "USD") == nil)
        #expect(DomesticIndex.listing(for: "VND") == nil)
        // PNJ names a venue here but is also a HOSE ticker, so it must not resolve to anything.
        #expect(DomesticIndex.listing(for: "PNJ") == nil)
    }

    @Test("A lượng is 37.5 grams and a troy ounce is 31.1034768, so one lượng is 1.2057 ounces")
    func weights() {
        // Spelled out rather than deferred to the constant, because the constant is exactly what a wrong
        // conversion would make plausible: at 1.0 the gap looks like a 20% premium and at 10 it looks like
        // a crash, and both render without complaint.
        #expect(GoldUnit.gramsPerLuong == 37.5)
        #expect(GoldUnit.gramsPerTroyOunce == 31.1034768)
        #expect(abs(GoldUnit.troyOuncesPerLuong - 1.2056528) < 1e-6)
        #expect(GoldUnit.chiPerLuong == 10)
    }

    @Test("The gold gap is SJC minus the world price converted through weight and the dollar")
    func goldGap() throws {
        let now = Date()
        let quotes = [
            "vietnam:SJC": quote("SJC", .vietnam, 144_000_000, at: now),
            "world:GOLD": quote("GOLD", .world, 4_341.63, at: now),
            "vietnam:USDVND": quote("USDVND", .vietnam, 26_410, at: now),
        ]
        let watched = [WatchedSymbol(symbol: "GOLDGAP", market: .vietnam, pinnedToMenuBar: false)]
        let gap = try #require(DerivedQuote.values(for: watched, from: quotes)["vietnam:GOLDGAP"])

        // 4,341.63 × 1.2056528 × 26,410 = 138,243,220 VND per lượng, against a bar at 144,000,000.
        #expect(abs(gap.price - 5_756_780) < 1_000)
        #expect(gap.market == .vietnam)
        // No reference, and that is the point: PNJ publishes no previous close, so a change figure here
        // could only be measured against a baseline this app made up.
        #expect(gap.reference == nil)
        #expect(gap.change == nil)
    }

    @Test("The gap is only as current as its stalest input, and absent until all three arrive")
    func goldGapInputs() throws {
        let now = Date()
        let saturday = now.addingTimeInterval(-36 * 3600)
        let watched = [WatchedSymbol(symbol: "GOLDGAP", market: .vietnam, pinnedToMenuBar: false)]

        // The world price ticks all weekend while the gold board sits at Saturday morning. Taking the
        // newest input would report a day-old gap as current and let it grey nothing out.
        let quotes = [
            "vietnam:SJC": quote("SJC", .vietnam, 144_000_000, at: saturday),
            "world:GOLD": quote("GOLD", .world, 4_341.63, at: now),
            "vietnam:USDVND": quote("USDVND", .vietnam, 26_410, at: now),
        ]
        let gap = try #require(DerivedQuote.values(for: watched, from: quotes)["vietnam:GOLDGAP"])
        #expect(gap.asOf == saturday)

        // Two thirds of an equation is not a number. A row on a dash says "not yet"; a gap computed from a
        // missing dollar rate would say 144,000,000 and look like the gold price itself.
        for missing in ["vietnam:SJC", "world:GOLD", "vietnam:USDVND"] {
            var partial = quotes
            partial[missing] = nil
            #expect(DerivedQuote.values(for: watched, from: partial).isEmpty)
        }
    }

    @Test("A derived row pulls its three inputs into the tracked list, without disturbing the watchlist")
    func trackedInputs() {
        let watched = [WatchedSymbol(symbol: "GOLDGAP", market: .vietnam, pinnedToMenuBar: false)]
        let tracked = DerivedQuote.tracked(watched)
        #expect(Set(tracked.map(\.id)) == ["vietnam:GOLDGAP", "vietnam:SJC", "world:GOLD", "vietnam:USDVND"])

        // A row the user already watches keeps its own entry — the pin especially, which the implicit copy
        // does not carry and would silently switch off if it replaced it.
        let both = [
            WatchedSymbol(symbol: "GOLD", market: .world, pinnedToMenuBar: true),
            WatchedSymbol(symbol: "GOLDGAP", market: .vietnam, pinnedToMenuBar: false),
        ]
        let merged = DerivedQuote.tracked(both)
        #expect(merged.filter { $0.id == "world:GOLD" }.count == 1)
        #expect(merged.first { $0.id == "world:GOLD" }?.pinnedToMenuBar == true)

        // Nothing is added for a watchlist with no derived row in it.
        let plain = [WatchedSymbol(symbol: "VCB", market: .vietnam, pinnedToMenuBar: false)]
        #expect(DerivedQuote.tracked(plain).map(\.id) == ["vietnam:VCB"])
    }

    @Test("Only a listed company has per-share fundamentals to look up")
    func fundamentalsApply() {
        #expect(watched("VCB", .vietnam).hasPerShareFundamentals)
        // SSI answers for "SJC" with some other company's figures — a P/B of 10,607 was what came back —
        // so this predicate is the only thing standing between a gold row and a nonsense ratio.
        #expect(!watched("SJC", .vietnam).hasPerShareFundamentals)
        #expect(!watched("USDVND", .vietnam).hasPerShareFundamentals)
        #expect(!watched("GOLDGAP", .vietnam).hasPerShareFundamentals)
        #expect(!watched("VNINDEX", .vietnam).hasPerShareFundamentals)
        #expect(!watched("GOLD", .world).hasPerShareFundamentals)
    }

    @Test("The domestic boards keep shop hours, not HOSE's, and do not stop for its lunch break")
    func hours() {
        // 12:00 ICT on a Wednesday: HOSE is in its lunch break, the gold shops are not.
        #expect(!MarketHours.isOpen(.vietnam, symbol: "VCB", at: ict(2026, 8, 5, 12, 0)))
        #expect(MarketHours.isOpen(.vietnam, symbol: "SJC", at: ict(2026, 8, 5, 12, 0)))
        #expect(MarketHours.isOpen(.vietnam, symbol: "USDVND", at: ict(2026, 8, 5, 12, 0)))
        // 08:45, before the board opens; and 16:00, after it closes.
        #expect(!MarketHours.isOpen(.vietnam, symbol: "VCB", at: ict(2026, 8, 5, 8, 45)))
        #expect(MarketHours.isOpen(.vietnam, symbol: "SJC", at: ict(2026, 8, 5, 8, 45)))
        #expect(MarketHours.isOpen(.vietnam, symbol: "SJC", at: ict(2026, 8, 5, 16, 0)))
        #expect(!MarketHours.isOpen(.vietnam, symbol: "SJC", at: ict(2026, 8, 5, 17, 0)))
        #expect(!MarketHours.isOpen(.vietnam, symbol: "SJC", at: ict(2026, 8, 5, 8, 29)))
        // Saturday counts, Sunday does not: PNJ's board carried an 11:00 Saturday timestamp and nothing
        // newer appeared on the Sunday.
        #expect(MarketHours.isOpen(.vietnam, symbol: "SJC", at: ict(2026, 8, 8, 11, 0)))
        #expect(!MarketHours.isOpen(.vietnam, symbol: "SJC", at: ict(2026, 8, 9, 11, 0)))
        #expect(!MarketHours.isOpen(.vietnam, symbol: "VCB", at: ict(2026, 8, 8, 11, 0)))
    }

    @Test("A domestic reading is never rebased onto a session boundary it does not have")
    func noPendingSessionRebase() {
        // Saturday's gold board, read on Sunday. A HOSE row here would be rebased flat, because its day has
        // rolled past its session — and doing that to a row with no reference at all would manufacture the
        // very "unchanged" reading the missing reference is there to avoid.
        let saturday = ict(2026, 8, 8, 11, 0)
        let sunday = ict(2026, 8, 9, 15, 0)
        let bar = quote("SJC", .vietnam, 144_000_000, at: saturday)
        #expect(bar.isFromCurrentSession(at: sunday))
        #expect(bar.rebasedForPendingSession(at: sunday).reference == nil)

        // The equity beside it still is rebased, which is the behaviour this must not have broken.
        let equity = quote("VCB", .vietnam, 59_700, reference: 59_000, at: ict(2026, 8, 7, 15, 0))
        #expect(equity.rebasedForPendingSession(at: sunday).reference == 59_700)
    }

    // MARK: - Helpers

    private func watched(_ symbol: String, _ market: Market) -> WatchedSymbol {
        WatchedSymbol(symbol: symbol, market: market, pinnedToMenuBar: false)
    }

    private func venueLabel(_ symbol: String) -> String {
        watched(symbol, .vietnam).venueLabel
    }

    private func quote(_ symbol: String, _ market: Market, _ price: Double,
                       reference: Double? = nil, at date: Date) -> Quote {
        Quote(symbol: symbol, market: market, price: price, reference: reference,
              ceiling: nil, floor: nil, volume: nil, asOf: date)
    }

    private func ict(_ y: Int, _ m: Int, _ d: Int, _ h: Int, _ min: Int) -> Date {
        var c = DateComponents()
        c.year = y; c.month = m; c.day = d; c.hour = h; c.minute = min
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = MarketHours.ict
        return cal.date(from: c)!
    }
}
