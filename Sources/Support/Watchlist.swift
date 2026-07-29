// Watchlist.swift — the user's chosen symbols, persisted to UserDefaults as JSON.
//
// Stored as one JSON blob under a single key rather than as parallel arrays, so adding a per-symbol
// field later (an alert threshold, a display alias) doesn't need a migration. The decode is
// deliberately forgiving: a blob written by a future version with extra keys still decodes, and a
// corrupt or absent blob falls back to the defaults instead of launching with an empty menu bar.

import Foundation
import Combine

@MainActor
final class Watchlist: ObservableObject {
    private static let key = "watchlist.v1"

    /// Shipped defaults: the two Vietnamese benchmarks a VN-based user checks first, one large-cap to
    /// show what an equity row looks like, and Bitcoin. Only VN-Index and BTC are pinned to the menu
    /// bar — three pinned rows already crowds a 15-inch menu bar once other apps have their items in.
    static let shipped: [WatchedSymbol] = [
        WatchedSymbol(symbol: "VNINDEX", market: .vietnam, pinnedToMenuBar: true),
        WatchedSymbol(symbol: "VN30",    market: .vietnam, pinnedToMenuBar: false),
        WatchedSymbol(symbol: "VCB",     market: .vietnam, pinnedToMenuBar: false),
        WatchedSymbol(symbol: "BTCUSDT", market: .crypto,  pinnedToMenuBar: true),
    ]

    @Published private(set) var symbols: [WatchedSymbol]

    init() {
        symbols = Self.load() ?? Self.shipped
    }

    /// The rows rendered in the menu bar, in watchlist order. Capped so a user who pins everything
    /// can't push the app's own item off the far left of the menu bar (macOS silently truncates the
    /// overflow, which reads as the app being broken rather than as a limit being hit).
    var pinned: [WatchedSymbol] {
        symbols.filter(\.pinnedToMenuBar).prefix(4).map { $0 }
    }

    /// Markets that currently have at least one watched symbol, so the reader only calls the sources
    /// it actually needs.
    var activeMarkets: Set<Market> {
        Set(symbols.map(\.market))
    }

    func add(_ symbol: String, market: Market) {
        let normalised = symbol.trimmingCharacters(in: .whitespaces).uppercased()
        guard !normalised.isEmpty else { return }
        let entry = WatchedSymbol(symbol: normalised, market: market, pinnedToMenuBar: false)
        guard !symbols.contains(where: { $0.id == entry.id }) else { return }
        symbols.append(entry)
        save()
    }

    func remove(_ entry: WatchedSymbol) {
        symbols.removeAll { $0.id == entry.id }
        save()
    }

    func togglePinned(_ entry: WatchedSymbol) {
        guard let i = symbols.firstIndex(where: { $0.id == entry.id }) else { return }
        symbols[i].pinnedToMenuBar.toggle()
        save()
    }

    func move(from source: IndexSet, to destination: Int) {
        symbols.move(fromOffsets: source, toOffset: destination)
        save()
    }

    /// Restore the shipped list — the escape hatch for a watchlist that's been edited into a mess.
    func resetToDefaults() {
        symbols = Self.shipped
        save()
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(symbols) else { return }
        UserDefaults.standard.set(data, forKey: Self.key)
    }

    private static func load() -> [WatchedSymbol]? {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode([WatchedSymbol].self, from: data),
              !decoded.isEmpty
        else { return nil }
        return decoded
    }
}
