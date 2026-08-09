// VNQuoteSource.swift — the `.vietnam` market's front door, which is three feeds rather than one.
//
// The same shape WorldQuoteSource took, and it arrived the same way. `Market` picks a source, and for a
// while that source could just be the VPS board. It cannot any more: the SJC gold bar is quoted by
// jewellers and the dollar rate by banks, and neither is on any exchange, so a market that used to mean
// "HOSE" now means "priced in dong, in Vietnam". Rather than teach `QuoteReader` about feeds — it plans per
// market, and a market fanning out to three upstreams would be a special case in the middle of the refresh
// loop — the split lives here, behind the same `QuoteSource` every other market satisfies.
//
// Routing is `DomesticIndex.listing(for:)`: a symbol in that table goes to its venue, everything else goes
// to the board, which is the feed that takes an arbitrary ticker. Guessing the other way round would be
// worse than useless — PNJ answers with its own product list no matter what is asked, so an unlisted
// symbol sent there would come back with somebody else's gold price rather than an honest miss.
//
// GOLDGAP is not routed anywhere, and must not be: it is computed from three of the rows above rather than
// fetched, and QuoteReader keeps it out of the plan entirely (see DerivedQuote). If one ever reaches this
// file it is a bug upstream, so it is dropped rather than sent to a feed that would answer for the wrong
// instrument.

import Foundation

struct VNQuoteSource: QuoteSource {

    private let board = VPSQuoteSource()
    private let pnj = PNJQuoteSource()
    private let vietcombank = VietcombankQuoteSource()

    func fetchQuotes(for symbols: [String]) async throws -> [Quote] {
        guard !symbols.isEmpty else { return [] }

        var wanted: [DomesticVenue?: [String]] = [:]
        for symbol in symbols where !DerivedQuote.isDerived(symbol) {
            wanted[DomesticIndex.listing(for: symbol)?.venue, default: []].append(symbol)
        }

        var quotes: [Quote] = []
        // The board first and on its own error path: it serves the whole equity watchlist in one request,
        // and a jeweller's board being unreachable is no reason to lose it. The reverse holds too, which is
        // why each venue is awaited separately rather than in one `try` — a market with three upstreams
        // should not go dark because the least important of them timed out.
        if let boardSymbols = wanted[nil] {
            quotes += try await board.fetchQuotes(for: boardSymbols)
        }
        if wanted[.pnj] != nil {
            quotes += try await pnj.fetchQuotes(for: ["SJC"])
        }
        if wanted[.vietcombank] != nil {
            quotes += try await vietcombank.fetchQuotes(for: ["USDVND"])
        }
        return quotes
    }

    func fetchHistory(for symbol: String) async throws -> [Double] {
        // Only the board publishes bars. A jeweller's board and a bank's rate sheet are step functions
        // updated a handful of times a day, with no series behind them and nothing a sparkline could say
        // about them that the price does not already.
        guard !DomesticIndex.isDomestic(symbol) else { return [] }
        return try await board.fetchHistory(for: symbol)
    }
}
