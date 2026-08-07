// InvestingBarSource.swift — intraday bars for the one instrument whose price feed has none.
//
//   https://api.investing.com/api/financialdata/68/historical/chart/?period=P1D&interval=PT1M&pointscount=120
//
// Not a `QuoteSource`, and the omission is the point. This asks one question — what has it done today — and
// says nothing about what anything is worth now. Spot gold is priced off TradingView's scanner, which is
// where the number the user reads comes from; borrowing a second upstream for the price as well would put
// two prices on one row with one of them implicit, which is the failure this app has a rule against. Bars
// are a different thing: the sparkline is normalised min-to-max inside its own 78×22pt box and carries no
// axis and no labels, so what it draws is a shape, and two honest quotes of the same OTC market agree about
// the shape to well inside a pixel.
//
// Same instrument, checked and not assumed (2026-08-07): pair 68's last minute closed 4,309.87 against the
// scanner's 4,309.43 and Swissquote's 4,309.02 bid. The neighbouring pair 8830 is the COMEX future at
// 4,369.12 — see the note on the GOLD row in WorldIndex, which is where the id is chosen.
//
// Established by probing it live the same day:
//
//   • `domain-id: www` IS REQUIRED. Without it the endpoint answers 500 with `Core API respond with invalid
//     status: 500`, which reads like an outage rather than a missing header. No key, cookie or referer is
//     needed beyond it, and it answers in about 0.3s.
//   • `pointscount` IS VALIDATED BUT NOT HONOURED. Anything outside {60, 70, 90, 110, 120, 140, 160} is a
//     500 naming the whitelist; anything inside it returns the same 288 one-minute bars. So the window is
//     fixed at the last 288 minutes — a rolling four-and-three-quarter hours, current to the minute, rather
//     than the session Yahoo gives the index rows. Left as it comes: gold's session is twenty-three hours
//     long, so honouring the boundary here would draw mostly last night, and 288 points is the same order
//     as the 391 the Dow already renders in that box.
//   • AN UNKNOWN PAIR IS A 500, not a 404 — `Core API respond with invalid status: 500`. There is no way to
//     tell a bad id from a bad day, which is another reason the id lives in a table that was verified once
//     rather than being derived from a symbol at runtime.

import Foundation

struct InvestingBarSource: Sendable {

    private static let base = "https://api.investing.com/api/financialdata"
    /// One minute per bar, over the largest window the endpoint will admit — see the header for why the
    /// count is a formality.
    private static let query = "period=P1D&interval=PT1M&pointscount=120"
    private static let headers = ["domain-id": "www"]

    /// Closes for `pair`, oldest-first. The pair id comes from `WorldIndex`, already resolved, rather than
    /// being looked up here: this source has no symbols of its own to reason about, and a second lookup
    /// would be a second chance to disagree with the router about which instrument is being drawn.
    func bars(pair: String) async throws -> [Double] {
        guard let url = URL(string: "\(Self.base)/\(pair)/historical/chart/?\(Self.query)") else {
            throw QuoteError.malformed("investing chart URL")
        }
        guard let root = try await HTTP.json(url, headers: Self.headers) as? [String: Any],
              let rows = root["data"] as? [[Any]] else {
            throw QuoteError.malformed("investing chart: expected data rows")
        }
        // Each row is [millis, open, high, low, close, volume, ...]; index 4 is the close, and volume is
        // always 0 because there is no central tape for spot gold to report one from.
        return rows.compactMap { row in
            guard row.count > 4, let close = HTTP.num(row[4]), close > 0 else { return nil }
            return close
        }
    }
}
