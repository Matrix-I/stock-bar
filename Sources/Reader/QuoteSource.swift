// QuoteSource.swift — the contract every venue implementation satisfies, and the errors they raise.
//
// One implementation per venue (VNQuoteSource, CryptoQuoteSource); the shared HTTP plumbing they both use
// is in HTTPClient.swift.

import Foundation

/// Anything that can turn a list of watched symbols into quotes. One implementation per venue.
protocol QuoteSource: Sendable {
    /// Fetch every symbol in `symbols` — implementations are expected to batch them into as few requests
    /// as the upstream allows, because request count, not bandwidth, is the scarce resource.
    func fetchQuotes(for symbols: [String]) async throws -> [Quote]
    /// Recent closes, oldest-first, for the popover sparkline. Empty when the upstream has none.
    func fetchHistory(for symbol: String) async throws -> [Double]
}

enum QuoteError: LocalizedError {
    case badStatus(Int)
    case malformed(String)
    case noData(String)

    var errorDescription: String? {
        switch self {
        case .badStatus(let code): return "server returned HTTP \(code)"
        case .malformed(let what): return "unexpected response shape (\(what))"
        case .noData(let symbol):  return "no data for \(symbol)"
        }
    }
}
