// QuoteSource.swift — the contract every venue implementation satisfies, and the errors they raise.
//
// One implementation per feed, behind a router per market where a market has several (VNQuoteSource,
// WorldQuoteSource); the shared HTTP plumbing they all use
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

extension Result {
    /// The error, for a source that fans out one request per symbol and has to tell "everything failed"
    /// from "one symbol isn't listed". Shared by the two world feeds, which both do exactly that.
    var failure: Failure? {
        switch self {
        case .success: return nil
        case .failure(let error): return error
        }
    }
}

/// One request per symbol, fanned out, keeping the two kinds of failure apart.
///
/// Some upstreams have no multi-symbol endpoint worth using — Yahoo's wants a crumb and a cookie scraped
/// from its web app, and TradingView's scanner is asked one instrument at a time — so both world feeds fan
/// out and both then face the same question, which is the only interesting thing here.
///
/// AN UNLISTED SYMBOL IS NOT A FAILED FETCH. A venue that has never heard of a ticker has answered
/// correctly, and reporting that as an error puts "Yahoo: no data for XYZ" under the panel while every
/// other row updates fine. So `noData` becomes an absence and everything else stays an error — but an
/// error is only worth surfacing if it took the whole batch down: one index failing while the others answer
/// is not worth a message, and that row ages visibly by itself. Hence the rule at the bottom, which is the
/// part that would drift if this were written out twice: throw only when NOTHING came back.
func fetchEachSymbol(
    _ symbols: [String],
    _ one: @escaping @Sendable (String) async throws -> Quote?
) async throws -> [Quote] {
    guard !symbols.isEmpty else { return [] }

    let results = await withTaskGroup(of: Result<Quote?, Error>.self) { group in
        for symbol in symbols {
            group.addTask {
                do {
                    return .success(try await one(symbol))
                } catch QuoteError.noData {
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
    if quotes.isEmpty, let failure = results.compactMap({ $0.failure }).first {
        throw failure
    }
    return quotes
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
