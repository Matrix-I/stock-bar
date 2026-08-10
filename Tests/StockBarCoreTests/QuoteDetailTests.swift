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

    @Test("The enrichment fields each add a row, in board order, and vanish with their data")
    func enrichedEquity() {
        // The full board row: the day's extremes, the volume-weighted average, and the net foreign flow.
        // Values pinned exactly, because two of them are easy to corrupt silently — High and Low swapped
        // read as a market that closed outside its own range, and a net flow without its sign reads as
        // buying whichever way it went.
        let full = Quote(symbol: "VCB", market: .vietnam, price: 54_600, reference: 54_100,
                         ceiling: 57_800, floor: 50_400, volume: 2_072_300, asOf: now,
                         high: 55_000, low: 53_900, average: 54_480,
                         foreignBought: 120_400, foreignSold: 166_295, foreignRoom: 82_155_290,
                         bid: 54_500, bidSize: 2_860, ask: 54_700, askSize: 510)
        let rows = QuoteDetail.rows(for: entry("VCB", .vietnam), quote: full,
                                    fundamentals: vcbFundamentals, now: now)
        #expect(rows.map(\.label) == ["Ceiling", "Floor", "Reference", "High", "Low", "Bid", "Ask",
                                      "Avg price", "Volume", "Foreign", "F. room",
                                      "P/E", "P/B", "Updated"])
        #expect(rows.first { $0.label == "High" }?.value == "55,000")
        #expect(rows.first { $0.label == "Low" }?.value == "53,900")
        // Price first, size behind the separator — and through the same volume abbreviation as the
        // Volume row, so 2,860 shares reads "3k" in both places or in neither.
        #expect(rows.first { $0.label == "Bid" }?.value == "54,500 · 3k")
        #expect(rows.first { $0.label == "Ask" }?.value == "54,700 · 510")
        #expect(rows.first { $0.label == "Avg price" }?.value == "54,480")
        #expect(rows.first { $0.label == "Foreign" }?.value == "−46k")
        #expect(rows.first { $0.label == "F. room" }?.value == "82.2M")

        // Each extreme is its own fact and its own row, so a feed reporting only one shows that one
        // rather than losing both.
        let halfRange = Quote(symbol: "VCB", market: .vietnam, price: 54_600, reference: 54_100,
                              ceiling: nil, floor: nil, volume: nil, asOf: now, high: 55_000)
        let sparse = QuoteDetail.rows(for: entry("VCB", .vietnam), quote: halfRange, now: now)
        #expect(sparse.map(\.label).contains("High"))
        #expect(!sparse.map(\.label).contains("Low"))
    }

    @Test("Crypto's extremes name their window, because its session is a rolling day")
    func cryptoRange() {
        let btc = Quote(symbol: "BTCUSDT", market: .crypto, price: 64_785, reference: 65_010,
                        ceiling: nil, floor: nil, volume: 5_388, asOf: now,
                        high: 65_192.54, low: 64_730.08,
                        bid: 64_790, bidSize: 12.33, ask: 64_790.01, askSize: 3.95)
        let rows = QuoteDetail.rows(for: entry("BTCUSDT", .crypto), quote: btc, now: now)
        // Next to a "24h open", an unlabelled High would invite comparing a day's extreme against a
        // session's — same shape, different window.
        #expect(rows.map(\.label) == ["24h open", "24h high", "24h low", "Bid", "Ask",
                                      "Volume", "Updated"])
        #expect(rows.first { $0.label == "24h high" }?.value == "65,192.54")
        #expect(rows.first { $0.label == "24h low" }?.value == "64,730.08")
        // Fractional sizes survive: a top-of-book of 12.33 coins must not read "12k" or vanish.
        #expect(rows.first { $0.label == "Bid" }?.value == "64,790.00 · 12")
    }

    @Test("The gold bar's bid is the dealer's buy-back, and says so")
    func dealerBoard() {
        // "Bid" under a shop's board would borrow an exchange's word for a jeweller's promise. The label
        // is also what makes the dealer spread legible: 144,000,000 over "Buy back 141,000,000" reads as
        // the three million dong it costs to change your mind.
        let bar = Quote(symbol: "SJC", market: .vietnam, price: 144_000_000, reference: nil,
                        ceiling: nil, floor: nil, volume: nil, asOf: now, bid: 141_000_000)
        let rows = QuoteDetail.rows(for: entry("SJC", .vietnam), quote: bar, now: now)
        #expect(rows.map(\.label) == ["Buy back", "Updated"])
        #expect(rows.first { $0.label == "Buy back" }?.value == "141,000,000")
        // And an exchange row keeps the exchange word — the label bends per venue, not per market.
        let vcb = Quote(symbol: "VCB", market: .vietnam, price: 54_600, reference: nil,
                        ceiling: nil, floor: nil, volume: nil, asOf: now, bid: 54_500)
        #expect(QuoteDetail.rows(for: entry("VCB", .vietnam), quote: vcb, now: now)
            .contains { $0.label == "Bid" })
    }

    @Test("The gap's card shows the subtraction it was born from, through the same formula")
    func goldGapCard() {
        // Inputs chosen so the expectations can be computed here independently: the card must agree with
        // DerivedQuote about the conversion, and the premium must be measured against the CONVERTED price
        // — against SJC it reads 4.0% instead of 4.2%, close enough to survive a glance and wrong.
        let converted = DerivedQuote.worldPerLuong(spotUSD: 4_000, usdVND: 25_000)
        let gap = Quote(symbol: "GOLDGAP", market: .vietnam, price: 144_000_000 - converted,
                        reference: nil, ceiling: nil, floor: nil, volume: nil, asOf: now)
        let context = [
            "vietnam:SJC": Quote(symbol: "SJC", market: .vietnam, price: 144_000_000, reference: nil,
                                 ceiling: nil, floor: nil, volume: nil, asOf: now),
            "world:GOLD": Quote(symbol: "GOLD", market: .world, price: 4_000, reference: nil,
                                ceiling: nil, floor: nil, volume: nil, asOf: now),
            "vietnam:USDVND": Quote(symbol: "USDVND", market: .vietnam, price: 25_000, reference: nil,
                                    ceiling: nil, floor: nil, volume: nil, asOf: now),
        ]
        let rows = QuoteDetail.rows(for: entry("GOLDGAP", .vietnam), quote: gap,
                                    context: context, now: now)
        #expect(rows.map(\.label) == ["SJC", "Spot in VND", "USDVND", "Premium", "Updated"])
        #expect(rows.first { $0.label == "SJC" }?.value == "144,000,000")
        #expect(rows.first { $0.label == "Spot in VND" }?.value
                == PriceFormat.price(converted, market: .vietnam, isIndex: false))
        #expect(rows.first { $0.label == "Premium" }?.value
                == PriceFormat.percent((144_000_000 - converted) / converted * 100))

        // Without the inputs there is no working to show, and a partial subtraction is not shown either —
        // the same all-or-nothing rule the gap's own value keeps. Partial specifically, not just empty:
        // each missing input must kill the block on its own, or a fallback quietly substituting one quote
        // for another would survive every test that only ever removes all three at once.
        let bare = QuoteDetail.rows(for: entry("GOLDGAP", .vietnam), quote: gap, now: now)
        #expect(bare.map(\.label) == ["Updated"])
        for missing in context.keys {
            var partial = context
            partial[missing] = nil
            let rows = QuoteDetail.rows(for: entry("GOLDGAP", .vietnam), quote: gap,
                                        context: partial, now: now)
            #expect(rows.map(\.label) == ["Updated"])
        }
    }

    @Test("A net flow keeps its sign, and zero is flat rather than a small positive")
    func netVolumeFormat() {
        #expect(PriceFormat.netVolume(132_407) == "+132k")
        #expect(PriceFormat.netVolume(-45_895) == "\u{2212}46k")
        #expect(PriceFormat.netVolume(0) == "0")
        #expect(PriceFormat.netVolume(-2_400_000) == "\u{2212}2.4M")
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
