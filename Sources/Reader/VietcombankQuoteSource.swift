// VietcombankQuoteSource.swift — the dollar rate, from Vietcombank's own published sheet.
//
//   https://www.vietcombank.com.vn/api/exchangerates?date=2026-08-09
//
// VCB's rate is the one Vietnamese reporting converts at, which is the only reason to prefer a single
// commercial bank's sheet over an interbank average: this row exists to make the gold gap comparable to the
// number in the papers, and the papers use this sheet.
//
// The older `portal.vietcombank.com.vn/.../pXML.aspx?b=10` feed carries the same table as XML and prints
// "Only one request every 5 minutes!" in a comment at the top of it. This JSON endpoint states no such
// limit, needs no key or header, and answers in one request — so it is the one used.
//
// Probed live on 2026-08-09:
//
//   • `sell` IS THE SIDE TO READ. Three columns come back per currency: `cash` (26,000), `transfer`
//     (26,030) and `sell` (26,410). Selling is what a buyer of dollars pays and what a conversion into
//     dong is quoted at, which is also the side DerivedQuote subtracts with.
//   • THE SHEET IS CARRIED FORWARD, never missing. A Sunday, a Saturday and 1 January all answer with a
//     full table — the last published one. That is what makes the previous-day request below safe: there
//     is no weekend or holiday hole to walk backwards over, so one extra request always finds a baseline.
//   • `UpdatedDate` IS NOT A PUBLICATION TIME and must not be used as `asOf`. It reads 23:00 on the
//     requested date, so during a session it is several hours in the FUTURE — which would make the row
//     un-ageable, since a negative interval can never exceed a staleness allowance. The fetch time is used
//     instead, exactly as it is for TradingView's scanner and for the same reason.

import Foundation

actor VietcombankQuoteSource: QuoteSource {

    private static let base = "https://www.vietcombank.com.vn/api/exchangerates"

    /// Yesterday's rate, cached by the ICT day it was fetched on. The baseline moves once a day, so
    /// re-fetching it every minute would double this row's request count for a number that cannot have
    /// changed — the same bargain VPSQuoteSource strikes for an index's previous close.
    private var referenceCache: (day: String, rate: Double)?

    func fetchQuotes(for symbols: [String]) async throws -> [Quote] {
        guard !symbols.isEmpty else { return [] }

        let now = Date()
        guard let rate = try await sellRate(on: now) else { throw QuoteError.noData("USDVND") }

        return [Quote(
            symbol: "USDVND",
            market: .vietnam,
            price: rate,
            // The previous day's sheet. Nil rather than a throw when it cannot be had: a rate with no
            // baseline is still worth showing, and the gap calculation downstream only reads `price`.
            reference: try? await previousRate(before: now),
            ceiling: nil,
            floor: nil,
            volume: nil,
            asOf: now       // see the header — the feed's own stamp is 23:00 on the requested day
        )]
    }

    /// Nothing. The sheet is published once or twice a day with no series behind it.
    func fetchHistory(for symbol: String) async throws -> [Double] {
        []
    }

    // MARK: - The sheet

    private func previousRate(before now: Date) async throws -> Double? {
        let yesterday = now.addingTimeInterval(-86400)
        let key = Self.day(yesterday)
        if let cached = referenceCache, cached.day == key { return cached.rate }
        guard let rate = try await sellRate(on: yesterday) else { return nil }
        referenceCache = (key, rate)
        return rate
    }

    private func sellRate(on date: Date) async throws -> Double? {
        guard let url = URL(string: "\(Self.base)?date=\(Self.day(date))") else {
            throw QuoteError.malformed("exchangerates URL")
        }
        guard let root = try await HTTP.json(url) as? [String: Any],
              let rows = root["Data"] as? [[String: Any]] else {
            throw QuoteError.malformed("exchangerates: expected a Data array")
        }
        guard let usd = rows.first(where: { $0["currencyCode"] as? String == "USD" }),
              let sell = HTTP.num(usd["sell"]), sell > 0 else { return nil }
        return sell
    }

    /// The ICT calendar day, as the endpoint spells it. In ICT and not the machine's zone: the sheet is
    /// published against a Vietnamese date, so a laptop in another time zone would otherwise ask for the
    /// wrong day for part of every evening.
    private static func day(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = MarketHours.ict
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }
}
