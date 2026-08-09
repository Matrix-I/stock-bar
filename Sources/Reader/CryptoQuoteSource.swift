// CryptoQuoteSource.swift — crypto pairs from Binance's public REST API. No key, no account, no
// signature: /api/v3/ticker/24hr and /api/v3/klines are both unauthenticated market-data endpoints.
//
//   Quotes  — https://api.binance.com/api/v3/ticker/24hr?symbols=["BTCUSDT","ETHUSDT"]
//             One request covers the whole crypto watchlist. Fields used: symbol, lastPrice,
//             openPrice (the price 24h ago, which is the reference a crypto change is quoted
//             against — there is no "previous close" on a venue that never closes), volume.
//   History — https://api.binance.com/api/v3/klines?symbol=BTCUSDT&interval=1m&limit=60
//             1-minute candles for the sparkline; index 4 of each row is the close.
//
// On rate limits: the REQUEST_WEIGHT ceiling is 6000 per minute, and a multi-symbol ticker/24hr call
// costs weight 4 regardless of how many symbols it names. Polling every 60 seconds therefore spends
// about 0.1% of the budget, so no backoff bookkeeping is warranted here beyond noticing a 429.
//
// Why REST polling rather than the WebSocket stream: the menu bar redraws once a minute, so a
// streaming feed would deliver ~60 updates per visible change. A stream is the right upgrade if this
// ever grows a live chart — the endpoint (wss://data-stream.binance.vision) does work from this
// machine through the corporate proxy, and URLSessionWebSocketTask answers Binance's 20-second server
// pings automatically — but for a once-a-minute label it is strictly more moving parts for no gain.

import Foundation

struct CryptoQuoteSource: QuoteSource {

    private static let base = "https://api.binance.com/api/v3"

    func fetchQuotes(for symbols: [String]) async throws -> [Quote] {
        guard !symbols.isEmpty else { return [] }
        let upper = symbols.map { $0.uppercased() }

        // Binance takes ONE symbol as `symbol=X` and several as `symbols=["X","Y"]` — a JSON array in
        // a query parameter, which needs the brackets and quotes percent-encoded. URLComponents leaves
        // `[`, `]` and `"` unescaped in a query value, and the endpoint rejects that with a 400, so the
        // query is encoded by hand here.
        let query: String
        if upper.count == 1 {
            query = "symbol=\(upper[0])"
        } else {
            let json = "[" + upper.map { "\"\($0)\"" }.joined(separator: ",") + "]"
            let encoded = json.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? json
            query = "symbols=\(encoded)"
        }
        guard let url = URL(string: "\(Self.base)/ticker/24hr?\(query)") else {
            throw QuoteError.malformed("ticker URL")
        }

        let root = try await HTTP.json(url)
        // A single-symbol request returns an object; a multi-symbol request returns an array. Normalise
        // so the parsing below has one shape to handle.
        let rows: [[String: Any]]
        if let array = root as? [[String: Any]] {
            rows = array
        } else if let object = root as? [String: Any] {
            rows = [object]
        } else {
            throw QuoteError.malformed("ticker: expected an object or array")
        }

        let now = Date()
        return rows.compactMap { row -> Quote? in
            guard let symbol = row["symbol"] as? String,
                  let last = HTTP.num(row["lastPrice"]), last > 0
            else { return nil }
            return Quote(
                symbol: symbol.uppercased(),
                market: .crypto,
                price: last,
                // openPrice is the price 24 hours ago on a rolling window — the baseline Binance's own
                // UI shows its percentage against. prevClosePrice exists too but tracks the previous
                // rolling window, which produces a change that disagrees with every other crypto UI.
                reference: HTTP.num(row["openPrice"]),
                ceiling: nil,       // no daily limit band on a crypto venue
                floor: nil,
                volume: HTTP.num(row["volume"]),
                asOf: now,
                // The extremes of the same rolling 24-hour window `openPrice` starts — one convention for
                // the whole row, so the range and the change describe the same stretch of time.
                high: HTTP.num(row["highPrice"]),
                low: HTTP.num(row["lowPrice"])
            )
        }
    }

    func fetchHistory(for symbol: String) async throws -> [Double] {
        // 60 one-minute candles — the last hour, which is what fits legibly in a sparkline that's ~90
        // points wide.
        guard let url = URL(string: "\(Self.base)/klines?symbol=\(symbol.uppercased())&interval=1m&limit=60") else {
            throw QuoteError.malformed("klines URL")
        }
        guard let rows = try await HTTP.json(url) as? [[Any]] else {
            throw QuoteError.malformed("klines: expected an array of arrays")
        }
        // Each kline is [openTime, open, high, low, close, volume, closeTime, ...]; index 4 is close.
        return rows.compactMap { $0.count > 4 ? HTTP.num($0[4]) : nil }
    }
}
