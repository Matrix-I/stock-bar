// TradingViewQuoteSource.swift — spot gold, from TradingView's scanner endpoint. The second of the two
// feeds behind `.world`; WorldQuoteSource picks between them, and YahooQuoteSource is the other.
//
//   https://scanner.tradingview.com/symbol?symbol=TVC%3AGOLD&fields=close,change_abs,volume
//
// It exists for one instrument, and only because Yahoo has no answer for it. Spot XAU/USD is not on the
// chart endpoint at any spelling — `XAUUSD=X`, `XAU=X` and `GCUSD=X` all 404 — and the COMEX front-month
// future that IS there quotes some sixty dollars above spot on the cost of carry. That is the right number
// for a futures trader and the wrong one for anybody comparing against a gold page, which is what this row
// is for. This endpoint returns exactly what TradingView draws as GOLD, to the cent.
//
// No key, no account, no cookie. Established by probing it live on 2026-08-07:
//
//   • IT IS REAL TIME. `update_mode` comes back `streaming`, and the price agreed with an independent spot
//     feed (Swissquote's XAU/USD bid) to within a few cents. There is nothing to add to the staleness
//     allowance here, unlike the ten-minute exchange delay on Yahoo's ICE data.
//   • THERE IS NO PREVIOUS CLOSE FIELD. `prev_close_price` answers null. The reference is recovered as
//     `close - change_abs`, which is the same subtraction the site itself displays; asking for `change`
//     (the percentage) instead would recover it through a division and lose precision for no reason.
//   • THERE ARE NO BARS. No history endpoint on this host answers — `/history` 404s and the charting data
//     comes over an authenticated websocket — so `fetchHistory` below returns nothing. Gold's sparkline is
//     drawn from investing.com instead (see InvestingBarSource and the GOLD row in WorldIndex); this source
//     never learned to draw one, it just stopped being asked.
//   • AN UNKNOWN SYMBOL IS A CLEAN 404 with `{"code":"symbol_not_exists"}`, so a typo can be told from a
//     dead feed exactly as it can on Yahoo.
//
// `time` is NOT the last tick. It reads 18:00 New York time — the start of the current trading day, which
// is itself useful confirmation of where the daily rollover falls (see MarketHours) but useless as an
// `asOf`: taken literally it would age the row out of the panel over the course of every session.

import Foundation

struct TradingViewQuoteSource: QuoteSource {

    private static let base = "https://scanner.tradingview.com/symbol"
    /// Everything one row needs, and nothing else. The endpoint returns precisely the fields asked for.
    /// `high`/`low` are the current trading day's — the one that began at the 18:00 New York rollover.
    private static let fields = "close,change_abs,volume,high,low"

    func fetchQuotes(for symbols: [String]) async throws -> [Quote] {
        // One instrument per scanner request, fanned out by `fetchEachSymbol` — the same shape as the Yahoo
        // source and, more to the point, the same rule about which failures are worth reporting.
        try await fetchEachSymbol(symbols) { try await self.fetchOne($0) }
    }

    /// Nothing: the scanner publishes no series — see the header. Nothing routes here today, because the
    /// one row on this feed takes its bars from investing.com, but the honest answer stays honest: an
    /// instrument added to this feed without a bars route should draw no sparkline rather than throw, since
    /// a missing shape is not a failed fetch.
    func fetchHistory(for symbol: String) async throws -> [Double] {
        []
    }

    // MARK: - One symbol

    private func fetchOne(_ symbol: String) async throws -> Quote {
        let wanted = WorldIndex.feedSymbol(for: symbol)
        // The colon in `TVC:GOLD` has to be percent-encoded; the endpoint decodes the query value before
        // resolving it, and `TVC%3AGOLD` answers 200.
        guard let encoded = wanted.addingPercentEncoding(withAllowedCharacters: .alphanumerics),
              let url = URL(string: "\(Self.base)?symbol=\(encoded)&fields=\(Self.fields)")
        else { throw QuoteError.malformed("scanner URL") }

        let root: Any
        do {
            root = try await HTTP.json(url)
        } catch QuoteError.badStatus(404) {
            // `{"code":"symbol_not_exists"}`. Reported as noData so the Add field can say "not listed"
            // rather than blaming the network.
            throw QuoteError.noData(symbol)
        }

        guard let object = root as? [String: Any] else {
            throw QuoteError.malformed("scanner: expected an object")
        }
        guard let price = HTTP.num(object["close"]) else { throw QuoteError.noData(symbol) }
        let change = HTTP.num(object["change_abs"])

        return Quote(
            symbol: Ticker.canonical(symbol),
            market: .world,
            // Reconstructed rather than read: see the header. nil when the feed omitted the change, which
            // leaves the row showing a bare price instead of inventing a move against an unknown baseline.
            price: price,
            reference: change.map { price - $0 },
            ceiling: nil,           // no daily limit band outside Vietnam
            floor: nil,
            // Spot gold is an OTC market with no central tape, so there is no volume to report; the field
            // comes back 0. Zero here means "nobody publishes this", not "nothing traded".
            volume: HTTP.num(object["volume"]).flatMap { $0 > 0 ? $0 : nil },
            // The fetch time, deliberately, because the feed's own `time` is the start of the trading day
            // and not the last print — see the header. The reading really is current to the second while
            // the market is open, which is the claim `asOf` is making.
            asOf: Date(),
            high: HTTP.num(object["high"]),
            low: HTTP.num(object["low"])
        )
    }
}
