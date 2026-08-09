// PNJQuoteSource.swift — the domestic gold bar, from PNJ's storefront API.
//
//   https://edge-api.pnj.io/ecom-frontend/v1/get-gold-price
//
// SJC's own board is the canonical source and cannot be read from this machine: sjc.com.vn is blocked by
// the Cloudflare Gateway this network runs behind, which returns its own block page rather than a refusal
// from the site. That is a policy on this laptop, not an outage, and it applies to URLSession exactly as it
// does to curl — the app goes through the same tunnel. So the bar is quoted through a retailer, and the
// venue line says PNJ rather than SJC because that is whose price this is.
//
// Probed live on 2026-08-09:
//
//   • NO KEY, NO HEADER, NO COOKIE, and it answers the whole product board in one request — twenty rows,
//     of which `masp: "SJC"` is the gold bar. The others are PNJ's own jewellery lines.
//   • PRICES ARE THOUSANDS OF DONG PER CHỈ. Nothing in the response says so, so it was checked rather than
//     assumed, and the check is worth repeating if this ever looks wrong: the plain 999.9 ring (`N24K`),
//     which carries almost no premium, read 14,390 against a world spot price that converts to 13,720 in
//     the same unit — 4.9% over, which is what a ring costs. Read as dong per lượng the same figure would
//     put domestic gold at a hundredth of the world price.
//   • THERE IS NO PREVIOUS CLOSE, and `?date=` is ignored — the same board comes back for any date. So this
//     row carries no reference and shows a bare price, rather than a change measured against a baseline
//     that would have to be invented.
//   • `updateDate` IS A REAL PUBLICATION TIME, `dd/MM/yyyy HH:mm:ss` in ICT, and it is used as `asOf`. It
//     read 11:00:38 on a Saturday and did not move again that day, which is what the eight-hour staleness
//     allowance in DomesticVenue is sized for: this is a board that changes in steps, not a feed.
//   • `chinhanh` reports which branch's prices these are (`hochiminh`). Not modelled — the bar is a
//     standardised product and the branches quote it alike — but it is why this file says PNJ's price and
//     not "the" price.

import Foundation

struct PNJQuoteSource: QuoteSource {

    private static let url = URL(string: "https://edge-api.pnj.io/ecom-frontend/v1/get-gold-price")!
    /// The SJC bar's row in PNJ's product list. Their code, not a ticker.
    private static let sjcProductCode = "SJC"

    func fetchQuotes(for symbols: [String]) async throws -> [Quote] {
        guard !symbols.isEmpty else { return [] }

        guard let root = try await HTTP.json(Self.url) as? [String: Any],
              let rows = root["data"] as? [[String: Any]] else {
            throw QuoteError.malformed("PNJ: expected a data array")
        }
        guard let bar = rows.first(where: { $0["masp"] as? String == Self.sjcProductCode }),
              let sell = HTTP.num(bar["giaban"]), sell > 0 else {
            throw QuoteError.noData("SJC")
        }

        return [Quote(
            symbol: "SJC",
            market: .vietnam,
            // The selling price — what a buyer pays, and the side the press compares against the world
            // price. `giamua` (the bid) is the other half of a spread this row does not model: one number
            // under a ticker has to be one side of the market, and it should be the same side the gap
            // calculation subtracts from.
            price: sell * 1000 * GoldUnit.chiPerLuong,
            reference: nil,     // see the header: the board publishes no previous close
            ceiling: nil,
            floor: nil,
            volume: nil,        // a shop's board, not a tape
            asOf: Self.parseUpdateDate(root["updateDate"]) ?? Date()
        )]
    }

    /// Nothing: a retail board is a step function published a few times a day, with no series behind it.
    func fetchHistory(for symbol: String) async throws -> [Double] {
        []
    }

    /// `08/08/2026 11:00:38`, in ICT. Falling back to the fetch time when it cannot be read is the safe
    /// direction: a wrong-but-recent `asOf` shows a healthy row, where a nil that defaulted to 1970 would
    /// grey it out permanently.
    private static func parseUpdateDate(_ value: Any?) -> Date? {
        guard let text = value as? String else { return nil }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = MarketHours.ict
        f.dateFormat = "dd/MM/yyyy HH:mm:ss"
        return f.date(from: text)
    }
}
