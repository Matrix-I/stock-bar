// HTTPClient.swift — the shared HTTP plumbing behind the data sources.
//
// On TLS: this machine sits behind a Cloudflare WARP/Gateway proxy that re-signs every HTTPS connection
// with "Gateway CA - Cloudflare Managed G1". That CA is installed and admin-trusted in
// /Library/Keychains/System.keychain, and URLSession consults the system trust store — so the app needs
// NO URLSessionDelegate, no custom trust evaluation and no pinning exceptions. (Verified: a plain
// URLSession request to both upstreams succeeds through the proxy. The runtimes that DO break here are
// the ones carrying private CA bundles — curl/openssl, Python/certifi, Node, the JVM — which is why the
// same URL fails from the shell but works from Swift.) Never add a `.serverTrust` override to "fix" a TLS
// error: it would be both unnecessary and a real regression.

import Foundation

/// The one URLSession every source shares.
///
/// `.ephemeral` keeps no on-disk cache or cookie jar — a quote is worthless the moment it's stale, and a
/// cached 200 would be actively harmful here. `waitsForConnectivity = false` matters for a menu-bar app:
/// with it enabled a request made while offline hangs until the network returns instead of failing, so the
/// UI could sit for minutes showing no error at all. A 12-second timeout is generous for these endpoints
/// (both answer in well under a second) while still failing inside one refresh cycle, so a wedged request
/// can never overlap the next tick.
enum HTTP {
    static let session: URLSession = {
        let c = URLSessionConfiguration.ephemeral
        c.timeoutIntervalForRequest = 12
        c.timeoutIntervalForResource = 20
        c.waitsForConnectivity = false
        c.httpAdditionalHeaders = [
            // Both upstreams are the JSON backends behind a public web board. They answer without a
            // browser User-Agent today, but sending a plain identifying one is both politer and less
            // likely to be caught by a future bot filter than sending none.
            "User-Agent": "StockBar/1.0 (macOS; personal use)",
            "Accept": "application/json",
        ]
        return URLSession(configuration: c)
    }()

    /// GET `url` and return the decoded JSON as an untyped tree.
    ///
    /// Deliberately JSONSerialization rather than Codable: the VPS board endpoint types its fields
    /// inconsistently — `lastPrice` arrives as a JSON number, `changePc` and `closePrice` as strings, and
    /// `r` as either — so a Decodable struct would need a custom init(from:) for nearly every field.
    /// Reading through `num(_:)` below handles both representations in one place instead.
    ///
    /// `headers` is for the one upstream that demands more than the shared defaults: investing.com's chart
    /// API answers 500 without a `domain-id`. Per-call rather than added to the session, because a header
    /// meant for one host has no business riding along on every request to the others.
    static func json(_ url: URL, headers: [String: String] = [:]) async throws -> Any {
        var request = URLRequest(url: url)
        for (field, value) in headers { request.setValue(value, forHTTPHeaderField: field) }
        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw QuoteError.badStatus(http.statusCode)
        }
        return try JSONSerialization.jsonObject(with: data)
    }

    /// Coerce a JSON value that might be a number *or* a numeric string into a Double. Returns nil for
    /// anything else, including the empty strings these endpoints use for "not applicable".
    static func num(_ value: Any?) -> Double? {
        switch value {
        case let d as Double: return d
        case let i as Int:    return Double(i)
        case let s as String: return Double(s.trimmingCharacters(in: .whitespaces))
        default:              return nil
        }
    }
}
