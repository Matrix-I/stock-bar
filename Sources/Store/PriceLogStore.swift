// PriceLogStore.swift — persistence for the series the app records itself. See Core/PriceLog.swift for
// what is recorded and why.
//
// Separate from Watchlist despite sharing UserDefaults, and under its own key. Two reasons, both learnt
// from WatchlistCoding's header: a decode failure here must not be able to cost anyone their watchlist,
// and a blob that grows with every price move should not sit inside one whose whole design is about never
// losing a row the user typed.
//
// A FAILED DECODE IS AN EMPTY LOG, not a stashed casualty. The watchlist is irreplaceable — nobody can
// reconstruct twenty hand-typed symbols — while this is a convenience the app rebuilds by simply
// continuing to run. Treating the two the same would be ceremony without a reason.

import Foundation

@MainActor
final class PriceLogStore: ObservableObject {

    private static let key = "priceLogs.v1"

    @Published private(set) var logs: PriceLogs

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let stored = defaults.data(forKey: Self.key).flatMap { try? JSONDecoder().decode(PriceLogs.self, from: $0) }
        logs = stored ?? PriceLogs()
    }

    private let defaults: UserDefaults

    /// Record what a poll saw, and persist only if anything moved.
    ///
    /// The write is gated on the return value rather than done unconditionally: a board that has not
    /// changed since this morning is the normal case, and re-encoding the whole blob once a minute for it
    /// would be the app's most pointless piece of disk traffic.
    /// `now` is the observing clock the spacing floor is measured on, defaulted here because this is the
    /// layer allowed to read a clock at all — Core is handed one. `Tools/uisnap` passes its own, which is
    /// what lets a seeded series be laid down across simulated days in one run.
    func record(_ entries: [WatchedSymbol], quotes: [String: Quote], now: Date = Date()) {
        var next = logs
        let changed = next.record(entries, quotes: quotes, now: now)
        guard changed else { return }
        logs = next
        save()
    }

    /// Forget the series for rows that have left the watchlist.
    func prune(keeping live: Set<String>) {
        var next = logs
        guard next.prune(keeping: live) else { return }
        logs = next
        save()
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(logs) else { return }
        defaults.set(data, forKey: Self.key)
    }
}
