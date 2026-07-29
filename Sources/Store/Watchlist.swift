// Watchlist.swift — the user's chosen symbols, persisted to UserDefaults as JSON.
//
// Stored as one JSON blob under a single key rather than as parallel arrays, so adding a per-symbol
// field later (an alert threshold, a display alias) doesn't need a migration. The decode is
// deliberately forgiving: a blob written by a future version with extra keys still decodes, and a
// corrupt or absent blob falls back to the defaults instead of launching with an empty menu bar.
//
// Everything here is storage and ordering. The one non-obvious rule — that a stored market can be wrong
// and has to be corrected — is in Core/WatchlistRepair.swift, where it is testable.

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
        let stored = Self.load()
        let repaired = stored.map(WatchlistRepair.repaired)
        symbols = repaired ?? Self.shipped
        // Write a repair straight back rather than only holding it in memory, so a corrected market
        // survives even if the list is never edited again.
        if let stored, let repaired, repaired != stored { save() }
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
        // The picker is a hint, not the last word: a ticker that could only have come from one venue is
        // filed there whatever was selected. Otherwise the picker's "VN" default silently turns a typed
        // crypto pair into a HOSE symbol that never resolves — see Market.inferred.
        let resolved = Market.inferred(for: normalised) ?? market
        let entry = WatchedSymbol(symbol: normalised, market: resolved, pinnedToMenuBar: false)
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

    /// Move one entry one place towards the front. Written as a swap rather than via
    /// `move(fromOffsets:toOffset:)` because that API's `toOffset` is an index in the *pre-removal*
    /// array — moving down one place needs `i + 2`, which is the kind of off-by-one that silently does
    /// nothing. The order matters beyond the list: the menu bar renders pinned symbols in watchlist
    /// order, and `pinned` keeps the first four, so reordering is also how you choose which pinned
    /// symbols get a slot.
    func moveUp(_ entry: WatchedSymbol) {
        guard let i = symbols.firstIndex(where: { $0.id == entry.id }), i > 0 else { return }
        symbols.swapAt(i, i - 1)
        save()
    }

    func moveDown(_ entry: WatchedSymbol) {
        guard let i = symbols.firstIndex(where: { $0.id == entry.id }), i < symbols.count - 1 else { return }
        symbols.swapAt(i, i + 1)
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
