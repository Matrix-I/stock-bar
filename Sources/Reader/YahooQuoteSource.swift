// YahooQuoteSource.swift — the world indices, from Yahoo Finance's chart endpoint. One of the two feeds
// behind `.world`; WorldQuoteSource picks between them, and TradingViewQuoteSource is the other.
//
//   https://query1.finance.yahoo.com/v8/finance/chart/%5EDJI?range=1d&interval=1m
//
// No key and no account, which is why this endpoint and not one of the paid index APIs. Two things about
// it were established by probing it live before this was written, and both shape the code:
//
//   • RANGE=1D IS LOAD-BEARING. `meta.chartPreviousClose` is the close before the FIRST BAR OF THE RANGE,
//     so the same request at range=5d hands back the close from six sessions ago — a plausible number that
//     produces a wrong change all day. At range=1d it is yesterday's close, and agrees with the separate
//     `meta.previousClose` field, which is the one read first here.
//   • ONE REQUEST PER SYMBOL. Yahoo's multi-symbol endpoint (v7/finance/quote?symbols=…) answers 401
//     without a crumb and cookie scraped from the web app, which is both fragile and impolite. A handful
//     of instruments at one request each, once a minute while a venue is open, is the cheaper trade — and
//     the reason QuoteReader gates per SYMBOL rather than per market, now that gold and the dollar index
//     keep the bucket "open" all night while the equity indices on this feed cannot move.
//
// The same response carries the intraday minute bars, so `fetchHistory` is the same URL read differently.
// A User-Agent is required: with none at all the endpoint answers 429. HTTPClient already sends one.
//
// This forwards whatever symbol it is given (mapped through WorldIndex for the caret spellings), so it
// serves any instrument Yahoo knows — a US stock included, and it is deliberately the fallback for a symbol
// the table has never heard of. Only the listed ones are advertised, because only they have a venue here,
// and without one the session gate can only guess.
//
// The mapped symbols are not all alphanumeric: `DX-Y.NYB` carries `-` and `.`, and the encoding below
// percent-escapes both. Yahoo decodes the path segment before routing, so `DX%2DY%2ENYB` answers 200 —
// checked live, because a 404 here is indistinguishable from a delisted symbol.

import Foundation

struct YahooQuoteSource: QuoteSource {

    private static let base = "https://query1.finance.yahoo.com/v8/finance/chart/"

    func fetchQuotes(for symbols: [String]) async throws -> [Quote] {
        guard !symbols.isEmpty else { return [] }

        // Concurrently, and keeping each symbol's outcome: a 404 means "no such symbol" and must not be
        // reported as a failure, while a transport error must — see the throw below.
        let results = await withTaskGroup(of: Result<Quote?, Error>.self) { group in
            for symbol in symbols {
                group.addTask {
                    do {
                        return .success(try await self.fetchOne(symbol))
                    } catch QuoteError.noData {
                        // The symbol is not listed. Nothing to show for it, nothing wrong with the feed.
                        return .success(nil)
                    } catch {
                        return .failure(error)
                    }
                }
            }
            var out: [Result<Quote?, Error>] = []
            for await r in group { out.append(r) }
            return out
        }

        let quotes = results.compactMap { try? $0.get() }.compactMap { $0 }
        // Surface a dead feed instead of silently keeping yesterday's rows. Only when NOTHING came back:
        // one index failing while the others answer is not worth a message under the panel, and the row
        // ages visibly by itself.
        if quotes.isEmpty, let failure = results.compactMap({ $0.failure }).first {
            throw failure
        }
        return quotes
    }

    func fetchHistory(for symbol: String) async throws -> [Double] {
        // The same minute bars the quote came from. Nulls are dropped rather than interpolated: Yahoo emits
        // one for every minute the index did not print, which before the open is most of the array, and a
        // zero there would draw a sparkline that dives to the floor and back.
        try await chart(symbol).closes
    }

    // MARK: - One symbol

    private func fetchOne(_ symbol: String) async throws -> Quote {
        let chart = try await chart(symbol)
        guard let price = chart.price else { throw QuoteError.noData(symbol) }
        return Quote(
            symbol: Ticker.canonical(symbol),
            market: .world,
            price: price,
            // previousClose first, chartPreviousClose second: they agree at range=1d, and the fallback is
            // there because only the latter is documented by the responses this was probed against.
            reference: chart.previousClose,
            ceiling: nil,           // no daily limit band outside Vietnam
            floor: nil,
            // Index "volume" is the summed turnover of the constituents, which Wall Street publishes and
            // the Nikkei feed reports as 0. Zero means "not published", not "nothing traded" — and the
            // dollar index, being computed rather than traded, omits the field entirely.
            volume: chart.volume.flatMap { $0 > 0 ? $0 : nil },
            // The feed's own timestamp for the last print, not the fetch time. It is real-time during a
            // session (measured: 0–4 seconds behind), and out of hours it is the close — which is what makes
            // the panel able to say a Tokyo row was last updated at 15:45 JST rather than "just now".
            asOf: chart.asOf ?? Date(),
            high: chart.high,
            low: chart.low
        )
    }

    /// The parsed pieces of one chart response.
    private struct Chart {
        let price: Double?
        let previousClose: Double?
        let volume: Double?
        let asOf: Date?
        let high: Double?
        let low: Double?
        let closes: [Double]
    }

    private func chart(_ symbol: String) async throws -> Chart {
        let wanted = WorldIndex.feedSymbol(for: symbol)
        // The caret has to be percent-encoded: URL(string:) accepts it, but Yahoo answers 404 for the raw
        // character.
        guard let encoded = wanted.addingPercentEncoding(withAllowedCharacters: .alphanumerics),
              let url = URL(string: "\(Self.base)\(encoded)?range=1d&interval=1m")
        else { throw QuoteError.malformed("chart URL") }

        let root: Any
        do {
            root = try await HTTP.json(url)
        } catch QuoteError.badStatus(404) {
            // Yahoo's answer for a symbol it doesn't carry, with an `error` object in the body. Reported as
            // noData so the Add field can say "not listed" rather than blaming the network.
            throw QuoteError.noData(symbol)
        }

        guard let object = root as? [String: Any],
              let chart = object["chart"] as? [String: Any]
        else { throw QuoteError.malformed("chart: expected an object") }
        guard let results = chart["result"] as? [[String: Any]], let result = results.first else {
            throw QuoteError.noData(symbol)
        }
        let meta = result["meta"] as? [String: Any] ?? [:]

        return Chart(
            price: HTTP.num(meta["regularMarketPrice"]),
            previousClose: HTTP.num(meta["previousClose"]) ?? HTTP.num(meta["chartPreviousClose"]),
            volume: HTTP.num(meta["regularMarketVolume"]),
            asOf: HTTP.num(meta["regularMarketTime"]).map { Date(timeIntervalSince1970: $0) },
            high: HTTP.num(meta["regularMarketDayHigh"]),
            low: HTTP.num(meta["regularMarketDayLow"]),
            closes: Self.closes(from: result)
        )
    }

    /// `indicators.quote[0].close`, with the nulls removed.
    private static func closes(from result: [String: Any]) -> [Double] {
        guard let indicators = result["indicators"] as? [String: Any],
              let quotes = indicators["quote"] as? [[String: Any]],
              let raw = quotes.first?["close"] as? [Any]
        else { return [] }
        return raw.compactMap { HTTP.num($0) }
    }
}
