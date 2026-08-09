// WatchedSymbol.swift — one user-configured row.
//
// Kept separate from `Quote` because this persists (UserDefaults, see Watchlist) while a Quote is
// transient: the watchlist survives a launch where every fetch failed.

import Foundation

struct WatchedSymbol: Codable, Sendable, Hashable, Identifiable {
    /// Identity is (market, symbol), not the symbol alone: the two namespaces can legitimately collide
    /// — a watchlist may hold both a VN ticker and a crypto pair spelled the same way — and the whole
    /// quote cache is keyed on this.
    var id: String { "\(market.rawValue):\(symbol)" }

    /// Exchange ticker (VN: "VCB", "VNINDEX") or venue pair (crypto: "BTCUSDT").
    let symbol: String
    let market: Market
    /// Whether this row is one of the ones rendered in the menu bar itself. The popover always shows
    /// every watched symbol; the menu bar shows only the pinned ones, because horizontal space there
    /// is the scarcest resource in the whole app.
    var pinnedToMenuBar: Bool

    /// Thresholds that notify when the price crosses them — see PriceAlert. At most one per direction, so
    /// this is a pair rather than a list in practice; kept as an array because the storage layer carries
    /// unknown fields forward and a fixed pair would have to be migrated to become anything else.
    ///
    var alerts: [PriceAlert] = []

    /// How much of this is owned and what it cost — see Holding. nil for a row that is only being watched,
    /// which is most of them.
    var holding: Holding?

    /// Decoded by hand for the optional keys, and the reason is the incident in WatchlistCoding's header
    /// read from the other end. A property default does NOT make a Codable key optional — Swift's
    /// synthesised `init(from:)` still requires it — so adding `alerts` made every row written before
    /// alerts existed undecodable. WatchlistCoding then did exactly what it promises: it kept them as
    /// foreign rows and showed the shipped defaults instead. Nothing was lost, and nothing was visible
    /// either. A new field on this type must always be read with `decodeIfPresent`.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        symbol = try c.decode(String.self, forKey: .symbol)
        market = try c.decode(Market.self, forKey: .market)
        pinnedToMenuBar = try c.decode(Bool.self, forKey: .pinnedToMenuBar)
        alerts = try c.decodeIfPresent([PriceAlert].self, forKey: .alerts) ?? []
        holding = try c.decodeIfPresent(Holding.self, forKey: .holding)
    }

    init(symbol: String, market: Market, pinnedToMenuBar: Bool,
         alerts: [PriceAlert] = [], holding: Holding? = nil) {
        self.symbol = symbol
        self.market = market
        self.pinnedToMenuBar = pinnedToMenuBar
        self.alerts = alerts
        self.holding = holding
    }

    /// Short label for the menu bar. VNINDEX is the one symbol whose ticker is too long to sit in a
    /// menu bar next to anything else, so it gets an alias; everything else uses its own ticker.
    var menuBarLabel: String {
        switch symbol.uppercased() {
        case "VNINDEX":  return "VNI"
        case "VN30":     return "VN30"
        case "HNXINDEX": return "HNX"
        case "BTCUSDT":  return "BTC"
        case "ETHUSDT":  return "ETH"
        // The gold gap's number is seven digits wide, so its ticker cannot also be seven characters —
        // between them they would take more menu bar than the rest of the watchlist put together.
        case "GOLDGAP":  return "GAP"
        default:
            // Crypto pairs are stored with their quote currency ("SOLUSDT"); the menu bar only has
            // room for the base asset, and USDT is the only quote currency this app requests.
            if market == .crypto, symbol.uppercased().hasSuffix("USDT") {
                return String(symbol.dropLast(4)).uppercased()
            }
            return symbol.uppercased()
        }
    }

    /// The venue line under the ticker in the popover.
    var venueLabel: String {
        switch market {
        case .crypto:  return "Binance"
        // The domestic rows first: they are on `.vietnam` but not on the board, and "HOSE" under a gold
        // price would name an exchange that has never quoted it.
        case .vietnam:
            if let listing = DomesticIndex.listing(for: symbol) { return listing.venue.label }
            return Ticker.isIndex(symbol) ? "Index" : "HOSE"
        // The exchange, not "Index": nearly every world row IS one, so the word would distinguish almost
        // nothing, while the venue says which clock the row is on — the answer to why the Dow sat still all
        // morning. For GOLD it carries a second meaning, and the more important one: "Spot" says the number
        // is the metal's own price and not the COMEX future sixty dollars above it.
        case .world:   return WorldIndex.listing(for: symbol)?.exchange.label ?? "World"
        }
    }

    var isIndex: Bool { Ticker.isIndex(symbol) }

    /// Whether a per-share fundamentals lookup means anything for this row. Only a listed Vietnamese
    /// company has an EPS: an index has no shares, and neither does a gold bar, a dollar rate or the gap
    /// between two of them — asking SSI about "SJC" would spend a request to be told nothing.
    var hasPerShareFundamentals: Bool {
        market == .vietnam && !isIndex && !DomesticIndex.isDomestic(symbol)
    }
}
