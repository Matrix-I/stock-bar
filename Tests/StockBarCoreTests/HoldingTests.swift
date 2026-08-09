// HoldingTests.swift — position arithmetic, and the states where it must refuse to answer.
//
// The arithmetic itself is three multiplications, and none of them is what these tests are about. The
// interesting cases are the half-entered ones: a quantity typed before the cost has been dug out, a cost of
// zero, a row with no position at all. Every one of those has an answer that renders perfectly well and is
// a lie — a "profit" equal to the entire market value, most of all.

import Testing
import Foundation
@testable import StockBarCore

@Suite("Holding")
struct HoldingTests {

    @Test("Value, cost and profit come out in the row's own currency")
    func arithmetic() {
        // 1,200 shares of VCB bought at 58,400, now 59,700.
        let holding = Holding(quantity: 1_200, averageCost: 58_400)
        #expect(holding.costBasis == 70_080_000)
        #expect(holding.marketValue(at: 59_700) == 71_640_000)
        #expect(holding.profit(at: 59_700) == 1_560_000)
        // 1,560,000 on a basis of 70,080,000 is 2.226%. The percentage is the figure a position is judged
        // by: a million and a half dong means nothing until you know what was staked to earn it.
        #expect(abs(holding.profitPercent(at: 59_700)! - 2.2260) < 0.001)
    }

    @Test("A fractional position is not rounded away")
    func fractional() {
        // A crypto position is rarely a whole coin, and a share-count formatter would show this as "0".
        let holding = Holding(quantity: 0.0035, averageCost: 61_000)
        #expect(abs(holding.marketValue(at: 64_800) - 226.8) < 0.001)
        #expect(abs(holding.profit(at: 64_800)! - 13.3) < 0.001)
        #expect(PriceFormat.quantity(0.0035) == "0.0035")
        // A whole share count still reads as one — no forced decimals.
        #expect(PriceFormat.quantity(1_200) == "1,200")
    }

    @Test("A position with no cost entered reports its size but refuses a profit")
    func costNotYetKnown() {
        // The dangerous state. With a basis of zero the "profit" is the whole market value, which renders
        // as an enormous gain on a position whose cost simply has not been typed in yet.
        let holding = Holding(quantity: 1_200, averageCost: 0)
        #expect(!holding.isEmpty)
        #expect(holding.marketValue(at: 59_700) == 71_640_000)
        #expect(holding.profit(at: 59_700) == nil)
        #expect(holding.profitPercent(at: 59_700) == nil)

        // The mirror: a cost with no quantity is not a position either.
        let noQuantity = Holding(quantity: 0, averageCost: 58_400)
        #expect(noQuantity.profit(at: 59_700) == nil)

        #expect(Holding(quantity: 0, averageCost: 0).isEmpty)
    }

    @Test("The detail card shows the position last, and only what it can stand behind")
    func detailRows() {
        let entry = WatchedSymbol(symbol: "VCB", market: .vietnam, pinnedToMenuBar: false,
                                  holding: Holding(quantity: 1_200, averageCost: 58_400))
        let labels = QuoteDetail.rows(for: entry, quote: quote(59_700)).map(\.label)
        // After everything about the instrument, before the timestamp: these four rows are the only ones on
        // the card that are true for exactly one person.
        #expect(labels.suffix(5) == ["Qty", "Avg cost", "Value", "P/L", "Updated"])

        let rows = QuoteDetail.rows(for: entry, quote: quote(59_700))
        #expect(rows.first { $0.label == "Qty" }?.value == "1,200")
        #expect(rows.first { $0.label == "Value" }?.value == "71,640,000")
        // Signed, grouped, and with the percentage beside it — both halves or neither.
        #expect(rows.first { $0.label == "P/L" }?.value == "+1,560,000 (+2.23%)")
    }

    @Test("A watched row with no position says nothing about one")
    func noHolding() {
        let entry = WatchedSymbol(symbol: "VCB", market: .vietnam, pinnedToMenuBar: false)
        let labels = QuoteDetail.rows(for: entry, quote: quote(59_700)).map(\.label)
        #expect(!labels.contains("Qty"))
        #expect(!labels.contains("P/L"))

        // Half a position shows half the rows rather than being suppressed entirely: someone who has typed
        // a share count and not yet a cost should see the count they typed.
        let partial = WatchedSymbol(symbol: "VCB", market: .vietnam, pinnedToMenuBar: false,
                                    holding: Holding(quantity: 1_200, averageCost: 0))
        let partialLabels = QuoteDetail.rows(for: partial, quote: quote(59_700)).map(\.label)
        #expect(partialLabels.contains("Qty"))
        #expect(partialLabels.contains("Value"))
        #expect(!partialLabels.contains("Avg cost"))
        #expect(!partialLabels.contains("P/L"))
    }

    @Test("A row stored before holdings existed still decodes, and keeps none")
    func decodesBlobWithoutHolding() throws {
        // The same trap `alerts` fell into: a Codable key that this build added is absent from every blob
        // written before it, and a required key there makes the whole row unreadable.
        let old = Data(#"{"symbol":"VCB","market":"vietnam","pinnedToMenuBar":false,"alerts":[]}"#.utf8)
        let entry = try JSONDecoder().decode(WatchedSymbol.self, from: old)
        #expect(entry.holding == nil)

        let owned = WatchedSymbol(symbol: "VCB", market: .vietnam, pinnedToMenuBar: false,
                                  holding: Holding(quantity: 1_200, averageCost: 58_400))
        let round = try JSONDecoder().decode(WatchedSymbol.self, from: try JSONEncoder().encode(owned))
        #expect(round == owned)
    }

    private func quote(_ price: Double) -> Quote {
        Quote(symbol: "VCB", market: .vietnam, price: price, reference: nil,
              ceiling: nil, floor: nil, volume: nil, asOf: Date())
    }
}
