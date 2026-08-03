// WatchlistCoding.swift — reads and writes the stored watchlist blob without deleting what it cannot read.
//
// The rule here was learnt by losing a list. v1.0.0 was installed in ~/Applications and registered as the
// login item while development carried on in a newer build, and that newer build added a `world` market.
// On the next restart the login item ran v1.0.0, whose decode of `[WatchedSymbol]` was all-or-nothing: one
// row with `"market":"world"` threw, `try?` turned the throw into nil, and the whole list became the four
// shipped defaults. Nothing said so. Every edit afterwards saved over the blob, so a dozen watched symbols
// were gone for good — destroyed by a build that was merely older, not broken.
//
// So: decoding is per row, and everything this build cannot account for is carried through to the next
// write. Two kinds of thing get carried. A whole row whose fields don't decode — a market from a later
// version — is kept verbatim at the position it held. And the original JSON of every row that DOES decode
// is kept too, so that a field a later version added, which this build has no property for, survives the
// act of saving. An older build now shows less than a newer one wrote, instead of deleting the difference.
//
// The cost is that the blob is round-tripped through JSONSerialization rather than JSONEncoder alone, so
// key order is not stable between writes. Nothing reads it positionally; only the decoder above does.

import Foundation

enum WatchlistCoding {

    /// A row this build could not decode, kept exactly as found, at the index it held. The index is where
    /// it goes back on the next write — clamped, because the list around it may have shrunk since.
    struct ForeignRow: Equatable, Sendable {
        let index: Int
        let json: Data
    }

    /// A row this build DID decode, kept as it was found and keyed by the id of the symbol it produced.
    /// A save merges this build's own fields over it, so the fields it doesn't model are not dropped.
    struct StoredRow: Equatable, Sendable {
        let id: String
        let json: Data
    }

    /// Everything a save has to put back untouched.
    struct Carried: Equatable, Sendable {
        var foreignRows: [ForeignRow] = []
        var storedRows: [StoredRow] = []

        /// What a list assembled from nothing carries: nothing.
        static let none = Carried()
    }

    struct Stored: Equatable, Sendable {
        var symbols: [WatchedSymbol]
        var carried: Carried
    }

    /// Parse a stored blob. Returns nil only when the blob is not a JSON array at all — the one case where
    /// there is nothing to salvage and the caller has to fall back to the shipped list.
    ///
    /// An empty array decodes to a `Stored` with no symbols rather than to nil, because "the user emptied
    /// the list" and "the blob is unreadable" are different situations and only the second is a loss.
    static func decode(_ data: Data) -> Stored? {
        guard let object = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]),
              let elements = object as? [Any]
        else { return nil }

        var symbols: [WatchedSymbol] = []
        var carried = Carried()

        for (index, element) in elements.enumerated() {
            // .fragmentsAllowed so that even a scalar where a row should be — junk, but somebody's junk —
            // is carried rather than quietly dropped.
            guard let row = try? JSONSerialization.data(withJSONObject: element,
                                                        options: [.fragmentsAllowed]) else { continue }
            if let symbol = try? JSONDecoder().decode(WatchedSymbol.self, from: row) {
                symbols.append(symbol)
                carried.storedRows.append(StoredRow(id: symbol.id, json: row))
            } else {
                carried.foreignRows.append(ForeignRow(index: index, json: row))
            }
        }

        return Stored(symbols: symbols, carried: carried)
    }

    /// Render `symbols` back to a blob, putting everything in `carried` back where it was.
    static func encode(_ symbols: [WatchedSymbol], carrying carried: Carried) -> Data? {
        let originals = Dictionary(carried.storedRows.map { ($0.id, $0.json) },
                                   uniquingKeysWith: { first, _ in first })

        var elements: [Any] = []
        for symbol in symbols {
            guard let mine = try? JSONEncoder().encode(symbol),
                  let parsed = try? JSONSerialization.jsonObject(with: mine),
                  var row = parsed as? [String: Any]
            else { return nil }

            // This build's values win every key it knows about; the original supplies only the keys it
            // doesn't. A row added in this session has no original and is written as-is.
            if let data = originals[symbol.id],
               let object = try? JSONSerialization.jsonObject(with: data),
               let original = object as? [String: Any] {
                row = original.merging(row) { _, mine in mine }
            }
            elements.append(row)
        }

        // Ascending, so each insertion is done against a list that already holds every earlier one and the
        // indices mean what they meant when they were recorded.
        for foreign in carried.foreignRows.sorted(by: { $0.index < $1.index }) {
            guard let object = try? JSONSerialization.jsonObject(with: foreign.json,
                                                                 options: [.fragmentsAllowed]) else { continue }
            elements.insert(object, at: min(foreign.index, elements.count))
        }

        return try? JSONSerialization.data(withJSONObject: elements)
    }
}
