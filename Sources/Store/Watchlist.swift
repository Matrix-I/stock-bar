// Watchlist.swift — the user's chosen symbols, persisted to UserDefaults as JSON.
//
// Stored as one JSON blob under a single key rather than as parallel arrays, so adding a per-symbol
// field later (an alert threshold, a display alias) doesn't need a migration. Reading and writing that
// blob is Core/WatchlistCoding.swift's job, and its header records the incident that shaped it: the rule
// is that a build never deletes what it cannot read, because an older copy of this app running at login
// once replaced a whole list with the shipped defaults over a single market value it didn't know.
//
// Everything here is storage and ordering. The one non-obvious rule — that a stored market can be wrong
// and has to be corrected — is in Core/WatchlistRepair.swift, where it is testable.

import Foundation
import Combine

@MainActor
final class Watchlist: ObservableObject {
    private static let key = "watchlist.v1"

    /// Where a blob that isn't JSON at all is put before the defaults are written over it. Kept rather
    /// than discarded because the alternative is what this file exists to prevent: a list that is simply
    /// gone, with nothing left to look at. Only the FIRST such blob is kept — a second bad launch would
    /// otherwise overwrite the evidence with the already-empty list that replaced it.
    private static let unreadableKey = "watchlist.v1.unreadable"

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

    /// The parts of the stored blob this build didn't produce — rows it couldn't decode, and the original
    /// JSON of the rows it could. Held for the lifetime of the store because every `save` has to put them
    /// back; see WatchlistCoding.
    private var carried: WatchlistCoding.Carried

    init() {
        let raw = UserDefaults.standard.data(forKey: Self.key)
        let stored = raw.flatMap(WatchlistCoding.decode)
        if let raw, stored == nil { Self.stashUnreadable(raw) }

        carried = stored?.carried ?? .none
        let repaired = stored.map { WatchlistRepair.repaired($0.symbols) }
        // An empty result is treated as no result: a blob holding only rows from a later version leaves
        // this build with nothing to show, and four defaults are better than an empty panel. The rows it
        // couldn't read are still in `carried`, so showing the defaults does not delete them.
        symbols = (repaired?.isEmpty == false ? repaired : nil) ?? Self.shipped
        // Write a repair straight back rather than only holding it in memory, so a corrected market
        // survives even if the list is never edited again.
        if let stored, let repaired, !repaired.isEmpty, repaired != stored.symbols { save() }
    }

    /// The rows rendered in the menu bar, in watchlist order. Capped so a user who pins everything
    /// can't push the app's own item off the far left of the menu bar (macOS silently truncates the
    /// overflow, which reads as the app being broken rather than as a limit being hit).
    var pinned: [WatchedSymbol] {
        symbols.filter(\.pinnedToMenuBar).prefix(4).map { $0 }
    }

    func add(_ symbol: String, market: Market) {
        // Trimmed, upper-cased and resolved to one spelling per instrument — see Ticker.canonical. The id is
        // "market:symbol", so an alias stored as typed would be a second row quoting the same index.
        let normalised = Ticker.canonical(symbol)
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

    /// Set or clear one direction's alert on a row. A nil threshold removes it.
    ///
    /// `currentPrice` is passed rather than looked up because this store holds no quotes and should not: it
    /// decides only what an alert IS, and PriceAlert's initialiser needs the price to know whether the
    /// condition already holds — an alert typed onto a price that has already crossed starts disarmed, so
    /// it reports the next crossing rather than the one on screen.
    func setAlert(_ entry: WatchedSymbol, direction: PriceAlert.Direction,
                  threshold: Double?, currentPrice: Double?) {
        guard let i = symbols.firstIndex(where: { $0.id == entry.id }) else { return }
        symbols[i].alerts.removeAll { $0.direction == direction }
        if let threshold, threshold > 0 {
            symbols[i].alerts.append(PriceAlert(direction: direction, threshold: threshold,
                                                currentPrice: currentPrice))
        }
        save()
    }

    /// Set the size of a position, or clear it with nil.
    ///
    /// One field at a time, matching the editor, because the two are typed separately and a method taking
    /// both would have to invent a value for whichever the user had not reached yet. A holding that ends up
    /// empty becomes nil rather than a pair of zeros, so everything downstream asks one question.
    func setHoldingQuantity(_ entry: WatchedSymbol, _ quantity: Double?) {
        updateHolding(entry) { $0.quantity = quantity ?? 0 }
    }

    func setHoldingCost(_ entry: WatchedSymbol, _ cost: Double?) {
        updateHolding(entry) { $0.averageCost = cost ?? 0 }
    }

    private func updateHolding(_ entry: WatchedSymbol, _ change: (inout Holding) -> Void) {
        guard let i = symbols.firstIndex(where: { $0.id == entry.id }) else { return }
        var holding = symbols[i].holding ?? Holding(quantity: 0, averageCost: 0)
        change(&holding)
        symbols[i].holding = holding.isEmpty ? nil : holding
        save()
    }

    /// Write back arming state after an evaluation. Separate from the editing methods above because this is
    /// the app talking to itself rather than the user changing anything, and because it must be a no-op when
    /// nothing moved — every write publishes, and republishing the list on each poll would redraw the whole
    /// panel once a minute for no reason.
    func applyAlertStates(_ updated: [WatchedSymbol]) {
        guard updated != symbols else { return }
        symbols = updated
        save()
    }

    /// Restore the shipped list — the escape hatch for a watchlist that's been edited into a mess.
    func resetToDefaults() {
        symbols = Self.shipped
        save()
    }

    private func save() {
        guard let data = WatchlistCoding.encode(symbols, carrying: carried) else { return }
        UserDefaults.standard.set(data, forKey: Self.key)
    }

    private static func stashUnreadable(_ raw: Data) {
        guard UserDefaults.standard.data(forKey: unreadableKey) == nil else { return }
        UserDefaults.standard.set(raw, forKey: unreadableKey)
        NSLog("StockBar: watchlist blob was unreadable — kept a copy under \(unreadableKey)")
    }
}
