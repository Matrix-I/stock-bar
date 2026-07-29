// WatchlistRepair.swift — makes a stored watchlist safe to use, before anything asks a venue about it.
//
// Extracted from Watchlist so it can be tested: the bug it fixes was invisible for a whole release and
// impossible to reproduce without hand-editing a plist. A crypto pair stored as `.vietnam` — what the
// Add row's "VN" default produced before `Watchlist.add` started inferring — makes the app ask a HOSE
// backend for a ticker that does not exist there, so the row shows a dash with nothing to explain it.
//
// Repairing on load (rather than only fixing new additions) means an existing watchlist heals itself
// instead of needing every bad row deleted and retyped.

import Foundation

enum WatchlistRepair {

    /// Refile entries whose market cannot serve them, and drop the duplicates that refiling can create.
    ///
    /// Returns the list unchanged — equal to its input — when there is nothing to fix, which is what
    /// lets the caller decide whether a write back to UserDefaults is warranted.
    static func repaired(_ entries: [WatchedSymbol]) -> [WatchedSymbol] {
        var seen = Set<String>()
        return entries.compactMap { entry in
            var corrected = entry
            if let inferred = Market.inferred(for: entry.symbol), inferred != entry.market {
                corrected = WatchedSymbol(symbol: entry.symbol, market: inferred,
                                          pinnedToMenuBar: entry.pinnedToMenuBar)
            }
            // The id is "market:symbol", so a repair can land on an id that is already in the list (a
            // watchlist can legitimately hold both a VN and a crypto BTCUSDT). Keep the first.
            return seen.insert(corrected.id).inserted ? corrected : nil
        }
    }
}
