// DomesticIndex.swift — the Vietnamese instruments that are not on an exchange, in one table.
//
// The sibling of WorldIndex, and for the same reason: a single instrument is spelled one way by the user,
// another by its feed, keeps hours that belong to neither HOSE nor the feed, and wants a venue line under
// its ticker. `.vietnam` stops being one venue here the way `.world` already stopped being one — the board
// serves the equities and the indices, a jeweller quotes the gold bar, and a bank publishes the dollar.
//
// THREE ROWS, and the third is the reason the other two are here. Domestic gold trades at a large premium
// over the world price — the number Vietnamese papers print daily as "chênh lệch" — and computing it needs
// the SJC bar, the world spot price and a dollar rate to convert between them. GOLDGAP is that subtraction,
// and it is the first row in this app whose value is computed rather than fetched (see DerivedQuote).
//
// NEITHER FEED PUBLISHES A PREVIOUS CLOSE, so SJC and GOLDGAP show a bare price with no change figure,
// which is the same choice made for a missing reference everywhere else: better an absent number than a
// move invented against an unknown baseline. Vietcombank is the exception — its endpoint takes a date, so
// USDVND is measured against the previous business day's sheet.
//
// EVERY SYMBOL AND ALIAS WAS CHECKED AGAINST THE VPS BOARD FIRST, and that check earned its keep twice:
// `USD` is a live UPCOM ticker and `VND` is VNDirect on HOSE, so neither could be an alias here. `PNJ` is
// a HOSE ticker too, which is why it appears below only as a venue label and never as a symbol. `SJC`,
// `USDVND`, `GOLDGAP`, `VANGSJC`, `GOLDSJC`, `TYGIA` and `GAP` all answer `[]`.

import Foundation

/// Who publishes a domestic row. A venue rather than a feed, because here the two coincide: there is no
/// exchange behind these numbers, only the institution that quotes them, and that institution IS the
/// answer to "whose price is this".
enum DomesticVenue: String, Sendable, CaseIterable {
    /// PNJ's retail board, which quotes the SJC bar among its own products.
    case pnj
    /// Vietcombank's published rate sheet.
    case vietcombank
    /// Nobody: the row is computed from other rows.
    case derived

    /// The line under the ticker in the panel.
    ///
    /// `PNJ` and not `SJC`, and the distinction is the same one the gold row upstairs makes between spot and
    /// a COMEX future, only smaller. The SJC bar is a standardised product and every retailer quotes it
    /// within a hair of the others, but this number is the one PNJ pays and charges, not the one SJC's own
    /// board shows — and sjc.com.vn cannot be read from this machine at all (its Cloudflare Gateway blocks
    /// the domain), so there is no version of this row that could claim otherwise.
    var label: String {
        switch self {
        case .pnj:          return "PNJ"
        case .vietcombank:  return "VCB"
        case .derived:      return "SJC − spot"
        }
    }

    /// How old a healthy quote from this venue is allowed to look, added to the staleness allowance the
    /// same way `WorldExchange.feedDelay` is.
    ///
    /// Eight hours, which is nearly the whole window below, and that is not a fudge — it is what these
    /// feeds are. PNJ's board carried `updateDate` 11:00:38 and did not move again that day; a bank rate
    /// sheet changes a handful of times between opening and close. Against the ordinary ninety-second
    /// allowance every one of these rows would render permanently dimmed within two minutes of the
    /// morning's publication, which is precisely the failure the dollar index already taught this app once.
    /// With data that updates in steps, "stale" can only usefully mean "the feed has stopped".
    var feedDelay: TimeInterval {
        switch self {
        case .pnj, .vietcombank, .derived: return 8 * 3600
        }
    }
}

/// One domestic instrument, as this app knows it.
struct DomesticIndex: Sendable, Equatable {
    /// What the user types, and what the watchlist stores.
    let symbol: String
    let venue: DomesticVenue
    /// Other accepted spellings. Kept short and checked against the board, for the reason in the header —
    /// the obvious abbreviations in this corner of the namespace are already taken by listed companies.
    let aliases: [String]
    /// What one unit of the price means, for the detail card. Spelled out because these are the only rows
    /// in the app whose unit is not obvious from the number: a lượng is 37.5 grams and a reader cannot be
    /// expected to infer that from 144,000,000.
    let unit: String
}

extension DomesticIndex {

    static let all: [DomesticIndex] = [
        // The SJC bar, in VND per lượng. PNJ quotes it in thousands of dong per chỉ; the conversion is in
        // PNJQuoteSource, and `GoldUnit` below is where the two Vietnamese weights are defined.
        DomesticIndex(symbol: "SJC", venue: .pnj,
                      aliases: ["VANGSJC", "GOLDSJC"], unit: "VND / lượng"),
        // The dollar, at Vietcombank's selling rate — the side of the sheet a buyer of dollars pays, and
        // the one the press quotes when it converts a world gold price into dong.
        DomesticIndex(symbol: "USDVND", venue: .vietcombank,
                      aliases: ["TYGIA", "USD/VND"], unit: "VND / USD"),
        // Chênh lệch: how much more a lượng of SJC costs than the same weight of world spot gold.
        DomesticIndex(symbol: "GOLDGAP", venue: .derived,
                      aliases: ["GAP"], unit: "VND / lượng"),
    ]

    /// The listing for a typed or stored symbol, by canonical name or by alias. nil for every exchange
    /// ticker, every index and everything on another market.
    static func listing(for symbol: String) -> DomesticIndex? {
        let s = symbol.trimmingCharacters(in: .whitespaces).uppercased()
        return all.first { $0.symbol == s || $0.aliases.contains(s) }
    }

    /// How old a healthy quote for `symbol` may look — see `DomesticVenue.feedDelay`. Zero for anything not
    /// in this table, which leaves the exchange rows on the ordinary allowance.
    static func feedDelay(for symbol: String) -> TimeInterval {
        listing(for: symbol)?.venue.feedDelay ?? 0
    }

    /// Whether `symbol` is one of these rows rather than something the VPS board serves. Read wherever
    /// `.vietnam` used to imply "on HOSE": the session clock, the day-boundary rebase, and the per-share
    /// fundamentals lookup are all wrong for a gold bar and a bank rate.
    static func isDomestic(_ symbol: String) -> Bool {
        listing(for: symbol) != nil
    }
}

/// The two Vietnamese gold weights and the one international one, in a single place because the gap
/// calculation multiplies by their ratio and a wrong constant there is invisible: the number stays
/// plausible and is simply wrong by a few percent.
enum GoldUnit {
    /// A lượng (also cây, or tael) is 37.5 grams by Vietnamese trade definition — an exact figure, not a
    /// rounded conversion.
    static let gramsPerLuong = 37.5
    /// Ten chỉ to the lượng, which is the unit a jeweller's board quotes in.
    static let chiPerLuong = 10.0
    /// The troy ounce, 31.1034768 grams exactly, which is what XAU/USD is priced in.
    static let gramsPerTroyOunce = 31.1034768

    /// ≈ 1.2057. Written as the division rather than as the quotient so the two definitions above stay
    /// visible: a reader can check the constant without trusting that someone divided correctly once.
    static let troyOuncesPerLuong = gramsPerLuong / gramsPerTroyOunce
}
