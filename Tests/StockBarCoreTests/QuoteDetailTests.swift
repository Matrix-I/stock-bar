// QuoteDetailTests.swift — what the hover card says, for each kind of instrument.
//
// The label list is asserted exactly rather than field by field. That is deliberate: the card replaced a
// tooltip whose labels were half Vietnamese (Trần / Sàn / TC), and the request was for English throughout,
// so a test that only checked the values would let one of them creep back unnoticed.

import Testing
import Foundation
@testable import StockBarCore

@Suite("QuoteDetail")
struct QuoteDetailTests {

    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func entry(_ symbol: String, _ market: Market) -> WatchedSymbol {
        WatchedSymbol(symbol: symbol, market: market, pinnedToMenuBar: false)
    }

    private var vcbFundamentals: Fundamentals {
        Fundamentals(earningsPerShare: 4210.03, bookValuePerShare: 26_866.44, year: 2025)
    }

    private func vcbQuote() -> Quote {
        Quote(symbol: "VCB", market: .vietnam, price: 54_600, reference: 54_100,
              ceiling: 57_800, floor: 50_400, volume: 2_072_300, asOf: now)
    }

    @Test("A Vietnamese equity shows its band, volume, both ratios and its age — in that order")
    func vietnameseEquity() {
        let rows = QuoteDetail.rows(for: entry("VCB", .vietnam), quote: vcbQuote(),
                                    fundamentals: vcbFundamentals, now: now)
        #expect(rows.map(\.label) == ["Ceiling", "Floor", "Reference", "Volume", "P/E", "P/B", "Updated"])
        #expect(rows.map(\.value) == ["57,800", "50,400", "54,100", "2.1M", "12.97", "2.03", "just now"])
    }

    @Test("P/E and P/B stay adjacent, so the card cannot split them across its two columns")
    func ratiosAreAdjacent() {
        // The card fills its first column and then its second. Whatever the row count, the two ratios have
        // to be next to each other or the pair lands one at the foot of the left column and one at the head
        // of the right — which is what the row order above exists to prevent.
        let rows = QuoteDetail.rows(for: entry("VCB", .vietnam), quote: vcbQuote(),
                                    fundamentals: vcbFundamentals, now: now)
        let pe = rows.firstIndex { $0.label == "P/E" }
        let pb = rows.firstIndex { $0.label == "P/B" }
        #expect(pe != nil && pb == pe! + 1)
        // And with seven rows the split is 4/3, so both fall in the second column.
        #expect(pe! >= (rows.count + 1) / 2)
    }

    @Test("Every label is English")
    func labelsAreEnglish() {
        // The tooltip this replaced said Trần / Sàn / TC. Non-ASCII in a label is the signal that one of
        // them has come back.
        let rows = QuoteDetail.rows(for: entry("VCB", .vietnam), quote: vcbQuote(),
                                    fundamentals: vcbFundamentals, now: now)
        #expect(rows.allSatisfy { $0.label.allSatisfy { $0.isASCII } })
    }

    @Test("An index has no band and no earnings to divide")
    func index() {
        let quote = Quote(symbol: "VNINDEX", market: .vietnam, price: 1704.68, reference: 1680.62,
                          ceiling: nil, floor: nil, volume: 412_000_000, asOf: now)
        let rows = QuoteDetail.rows(for: entry("VNINDEX", .vietnam), quote: quote, now: now)
        #expect(rows.map(\.label) == ["Reference", "Volume", "Updated"])
        // Index precision, the same two decimals the row itself shows.
        #expect(rows[0].value == "1,680.62")
    }

    @Test("A crypto pair's baseline is named for what it is")
    func crypto() {
        // Binance quotes its change against the price 24 hours ago on a rolling window. Calling that
        // "Reference" would imply a previous close, which a venue that never closes does not have.
        let quote = Quote(symbol: "BTCUSDT", market: .crypto, price: 64_134, reference: 63_000,
                          ceiling: nil, floor: nil, volume: 12_500, asOf: now)
        let rows = QuoteDetail.rows(for: entry("BTCUSDT", .crypto), quote: quote, now: now)
        #expect(rows.map(\.label) == ["24h open", "Volume", "Updated"])
    }

    @Test("A crypto pair is never given a valuation, whatever it is handed")
    func cryptoIsNeverValued() {
        // Guarded inside rows(for:) as well as at the fetch, so the invariant holds however the caller is
        // wired up.
        let quote = Quote(symbol: "BTCUSDT", market: .crypto, price: 64_134, reference: 63_000,
                          ceiling: nil, floor: nil, volume: 12_500, asOf: now)
        let rows = QuoteDetail.rows(for: entry("BTCUSDT", .crypto), quote: quote,
                                    fundamentals: vcbFundamentals, now: now)
        #expect(rows.contains { $0.label == "P/E" } == false)
        #expect(rows.contains { $0.label == "P/B" } == false)
    }

    @Test("A world index closed yesterday, and the card says so in those words")
    func worldIndex() {
        // "Reference" is a VN board's published baseline the band is cut from, and "24h open" is a rolling
        // window. Neither describes the Dow, which simply has a previous close.
        let quote = Quote(symbol: "DJI", market: .world, price: 51_916.15, reference: 51_594.14,
                          ceiling: nil, floor: nil, volume: 261_728_310, asOf: now)
        let rows = QuoteDetail.rows(for: entry("DJI", .world), quote: quote,
                                    fundamentals: vcbFundamentals, now: now)
        #expect(rows.map(\.label) == ["Prev close", "Volume", "Updated"])
        // Two decimals and grouped thousands, the way every board prints an index.
        #expect(rows[0].value == "51,594.14")
        // No valuation, whatever the dictionary happens to hold against its id.
        #expect(rows.contains { $0.label == "P/E" } == false)
    }

    @Test("With no fundamentals the card simply loses two rows")
    func withoutFundamentals() {
        let rows = QuoteDetail.rows(for: entry("VCB", .vietnam), quote: vcbQuote(), now: now)
        #expect(rows.map(\.label) == ["Ceiling", "Floor", "Reference", "Volume", "Updated"])
    }

    @Test("With no quote there is nothing to say")
    func withoutAQuote() {
        // The caller renders its own message rather than being handed a row that is really a sentence.
        #expect(QuoteDetail.rows(for: entry("VCB", .vietnam), quote: nil, now: now).isEmpty)
    }

    @Test("The age is measured against the caller's clock, not the machine's")
    func ageIsInjected() {
        let rows = QuoteDetail.rows(for: entry("VCB", .vietnam), quote: vcbQuote(),
                                    now: now.addingTimeInterval(600))
        #expect(rows.last?.value == "10m ago")
    }
}
