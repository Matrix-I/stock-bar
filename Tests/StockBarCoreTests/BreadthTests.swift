// BreadthTests.swift — the counting, and the two ways a breadth figure lies quietly.
//
// The first is folding untraded stocks into "unchanged": on the session this was built against, 46 of 428
// HOSE tickers had never matched, so a three-way count would have reported 109 flat where 63 were. The
// second is a denominator that shrinks — dropping the untraded rows instead of counting them makes every
// ratio computed downstream quietly wrong, and nothing about the number would look off.

import Testing
import Foundation
@testable import StockBarCore

@Suite("Breadth")
struct BreadthTests {

    private func quote(_ symbol: String, price: Double, reference: Double?,
                       volume: Double? = nil, average: Double? = nil,
                       bought: Double? = nil, sold: Double? = nil) -> Quote {
        Quote(symbol: symbol, market: .vietnam, price: price, reference: reference,
              ceiling: nil, floor: nil, volume: volume, asOf: Date(),
              average: average, foreignBought: bought, foreignSold: sold)
    }

    @Test("The floor's turnover is volume against the price it was traded at, not the price now")
    func turnover() {
        let quotes = [
            quote("A", price: 61_000, reference: 60_000, volume: 1_000, average: 60_500),
            quote("B", price: 59_000, reference: 60_000, volume: 2_000, average: 59_500),
            // Untraded, and it must contribute nothing without being skipped — a row dropped here would
            // also vanish from the counts, which is the bug the fetchBoardRows split exists to prevent.
            quote("C", price: 0, reference: 60_000, volume: 0, average: 0),
        ]
        let b = Breadth.count(floor: "HOSE", quotes: quotes)
        // 1,000 × 60,500 + 2,000 × 59,500 = 179,500,000. Against `price` instead of `average` it would
        // read 179,000,000 — close enough to look right and wrong every single session.
        #expect(b.tradedValue == 179_500_000)
        #expect(b.total == 3)
    }

    @Test("A board that published no totals reports nil, which is not the same as a floor that traded nothing")
    func silenceIsNotZero() {
        let quotes = [quote("A", price: 61_000, reference: 60_000),
                      quote("B", price: 59_000, reference: 60_000)]
        let b = Breadth.count(floor: "HOSE", quotes: quotes)
        // The counts still stand — those need only a price and a reference.
        #expect(b.up == 1 && b.down == 1)
        // But nothing said what traded, and "0 tỷ" on the card would be a claim the feed never made.
        #expect(b.tradedValue == nil)
        #expect(b.foreignBought == nil)
        #expect(b.foreignSold == nil)
    }

    @Test("Foreign flow is summed as two sides, because the net hides the size of both")
    func foreignSides() {
        let quotes = [
            quote("A", price: 61_000, reference: 60_000, bought: 500_000, sold: 100_000),
            quote("B", price: 59_000, reference: 60_000, bought: 200_000, sold: 900_000),
        ]
        let b = Breadth.count(floor: "HOSE", quotes: quotes)
        #expect(b.foreignBought == 700_000)
        #expect(b.foreignSold == 1_000_000)
        // A net of −300,000 would be the same on a floor that traded 300,000 shares and on one that
        // traded 1.7 million. The card shows both sides so those two days do not look alike.
        #expect(b.foreignBought! - b.foreignSold! == -300_000)
    }

    @Test("Up, down, flat and never-traded are four counts, not three")
    func countsFourWays() {
        let quotes = [
            quote("A", price: 61_000, reference: 60_000),   // up
            quote("B", price: 62_000, reference: 60_000),   // up
            quote("C", price: 59_000, reference: 60_000),   // down
            quote("D", price: 60_000, reference: 60_000),   // flat
            // lastPrice 0 is how the board says "no match yet". Counting this as flat is the mistake:
            // on a real HOSE session it would have moved 46 tickers into a flat count of 63.
            quote("E", price: 0, reference: 60_000),
        ]
        let b = Breadth.count(floor: "HOSE", quotes: quotes)
        #expect(b.up == 2)
        #expect(b.down == 1)
        #expect(b.unchanged == 1)
        #expect(b.untraded == 1)
        // The untraded row stays in the total and out of `traded`, so neither denominator is silently
        // wrong: the floor really has five listings and only four have said anything.
        #expect(b.total == 5)
        #expect(b.traded == 4)
        #expect(b.floor == "HOSE")
    }

    @Test("A row with no reference is not counted at all")
    func referenceIsRequired() {
        // Without a baseline there is nothing to be up or down against, so such a row must not fall into
        // any bucket — least of all "unchanged", which would be an assertion about a comparison never made.
        let b = Breadth.count(floor: "HOSE", quotes: [
            quote("A", price: 61_000, reference: nil),
            quote("B", price: 61_000, reference: 0),
            quote("C", price: 61_000, reference: 60_000),
        ])
        #expect(b.total == 1)
        #expect(b.up == 1)
    }

    @Test("The advance/decline ratio refuses an empty session rather than answering zero")
    func ratio() {
        let mixed = Breadth(floor: "HOSE", up: 176, down: 143, unchanged: 63, untraded: 46)
        #expect(abs(try! #require(mixed.advanceDeclineRatio) - 1.2308) < 0.001)

        // Before the open nothing has traded. Zero would claim decliners led; the truth is that the
        // question has no answer yet.
        let preOpen = Breadth(floor: "HOSE", up: 0, down: 0, unchanged: 0, untraded: 404)
        #expect(preOpen.advanceDeclineRatio == nil)

        // All advancers and no decliners is unbounded rather than a division by zero.
        let allUp = Breadth(floor: "HOSE", up: 12, down: 0, unchanged: 0, untraded: 0)
        #expect(allUp.advanceDeclineRatio == .infinity)
    }

    @Test("Only an index whose constituents this app can list gets a breadth line")
    func floorMapping() {
        #expect(Breadth.floor(for: "VNINDEX") == "HOSE")
        #expect(Breadth.floor(for: "vnindex") == "HOSE")     // canonicalised like every other lookup
        #expect(Breadth.floor(for: "HNXINDEX") == "HNX")
        // VN30 is thirty of HOSE's four hundred and this app has no membership list for it. Showing HOSE
        // breadth under it would label a count of 404 as if it described 30 — a wrong denominator that
        // renders perfectly.
        #expect(Breadth.floor(for: "VN30") == nil)
        #expect(Breadth.floor(for: "VCB") == nil)
        #expect(Breadth.floor(for: "DJI") == nil)
    }

    @Test("The card shows the counts under the floor's own name, and hides an empty untraded line")
    func detailRows() {
        let entry = WatchedSymbol(symbol: "VNINDEX", market: .vietnam, pinnedToMenuBar: false)
        let index = Quote(symbol: "VNINDEX", market: .vietnam, price: 1_768.06, reference: 1_764.78,
                          ceiling: nil, floor: nil, volume: 652_000, asOf: Date())
        let full = Breadth(floor: "HOSE", up: 176, down: 143, unchanged: 63, untraded: 46)
        let labels = QuoteDetail.rows(for: entry, quote: index, breadth: full).map(\.label)
        // Named by floor, so the card can never imply a breadth wider than the list it came from.
        #expect(labels.contains("HOSE up"))
        #expect(labels.contains("HOSE down"))
        #expect(labels.contains("No trade"))

        let rows = QuoteDetail.rows(for: entry, quote: index, breadth: full)
        #expect(rows.first { $0.label == "HOSE up" }?.value == "176")
        #expect(rows.first { $0.label == "No trade" }?.value == "46")

        // Mid-session there is often nothing untraded left, and a "No trade 0" line is chrome.
        let dense = Breadth(floor: "HOSE", up: 200, down: 150, unchanged: 54, untraded: 0)
        #expect(!QuoteDetail.rows(for: entry, quote: index, breadth: dense).map(\.label).contains("No trade"))

        // And a row with no breadth to show is unchanged from before the feature existed.
        #expect(!QuoteDetail.rows(for: entry, quote: index).map(\.label).contains("HOSE up"))
    }
}
