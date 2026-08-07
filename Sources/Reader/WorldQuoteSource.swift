// WorldQuoteSource.swift — the `.world` market's front door, which is now two feeds rather than one.
//
// `Market` picks a source, and for a while that source could just be Yahoo. It cannot any more: spot gold
// is not on Yahoo at any spelling, so GOLD comes from TradingView's scanner while everything else stays on
// the chart endpoint. Rather than teach `QuoteReader` about feeds — it plans per market, and a market that
// fanned out to two upstreams would be a special case in the middle of the refresh loop — the split lives
// here, behind the same `QuoteSource` the other markets satisfy.
//
// The routing table is `WorldIndex.feed(for:)`, so adding an instrument on a new upstream stays what it
// already is: one row in the listing table, plus the source itself. Anything unlisted goes to Yahoo, which
// is the feed that will take an arbitrary symbol.
//
// The split runs one level deeper than "one feed per row", because price and bars are separate capabilities
// and gold needs them from separate places: the scanner that quotes it best publishes no series. So
// `fetchHistory` routes on `WorldIndex.bars(for:)` instead, which normally sends it straight back to the
// price feed and for gold sends it to investing.com.
//
// `fetchQuotes` deliberately does NOT swallow one feed's error when the other answered — the reader shows
// the message under the panel and keeps the rows it has, which is the right outcome when half the world
// bucket is unreachable. A failure to draw a sparkline is not in that class and never reaches here:
// `QuoteReader.refreshHistory` drops it, because a missing shape next to a good price is not worth a
// message.

import Foundation

struct WorldQuoteSource: QuoteSource {

    private let yahoo = YahooQuoteSource()
    private let tradingView = TradingViewQuoteSource()
    private let investing = InvestingBarSource()

    func fetchQuotes(for symbols: [String]) async throws -> [Quote] {
        guard !symbols.isEmpty else { return [] }

        let byFeed = Dictionary(grouping: symbols) { WorldIndex.feed(for: $0) }
        var quotes: [Quote] = []
        // Sequential over at most two feeds, and each source already fans its own symbols out concurrently,
        // so the only thing a task group would overlap here is one request against another feed's batch.
        for feed in WorldFeed.allCases {
            guard let wanted = byFeed[feed], !wanted.isEmpty else { continue }
            quotes += try await source(for: feed).fetchQuotes(for: wanted)
        }
        return quotes
    }

    func fetchHistory(for symbol: String) async throws -> [Double] {
        switch WorldIndex.bars(for: symbol) {
        case .fromPriceFeed:
            return try await source(for: WorldIndex.feed(for: symbol)).fetchHistory(for: symbol)
        case .investing(let pair):
            return try await investing.bars(pair: pair)
        }
    }

    private func source(for feed: WorldFeed) -> any QuoteSource {
        switch feed {
        case .yahoo:       return yahoo
        case .tradingView: return tradingView
        }
    }
}
