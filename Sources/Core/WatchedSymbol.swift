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

    /// Short label for the menu bar. VNINDEX is the one symbol whose ticker is too long to sit in a
    /// menu bar next to anything else, so it gets an alias; everything else uses its own ticker.
    var menuBarLabel: String {
        switch symbol.uppercased() {
        case "VNINDEX":  return "VNI"
        case "VN30":     return "VN30"
        case "HNXINDEX": return "HNX"
        case "BTCUSDT":  return "BTC"
        case "ETHUSDT":  return "ETH"
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
        case .vietnam: return Ticker.isIndex(symbol) ? "Index" : "HOSE"
        // The exchange, not "Index": nearly every world row IS one, so the word would distinguish almost
        // nothing, while the venue says which clock the row is on — the answer to why the Dow sat still all
        // morning. For GOLD it carries a second meaning, and the more important one: "Spot" says the number
        // is the metal's own price and not the COMEX future sixty dollars above it.
        case .world:   return WorldIndex.listing(for: symbol)?.exchange.label ?? "World"
        }
    }

    var isIndex: Bool { Ticker.isIndex(symbol) }
}
