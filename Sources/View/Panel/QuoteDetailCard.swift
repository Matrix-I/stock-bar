// QuoteDetailCard.swift — the panel that opens under a row while the pointer rests on it.
//
// It replaced the row's `.help()` tooltip. AppKit holds a tooltip back for one to two seconds and then
// draws it in its own window, wherever the pointer happens to be; this appears at once, in the panel, under
// the row it describes. What it says is QuoteDetail's decision — this file only lays it out.
//
// Two columns rather than one because a Vietnamese equity has seven things worth saying, and seven stacked
// rows would be taller than the quote row they annotate.

import SwiftUI

struct QuoteDetailCard: View {
    let rows: [QuoteDetail.Row]

    var body: some View {
        Group {
            if rows.isEmpty {
                // A pinned symbol whose fetch has never succeeded. Saying so is the point of hovering it.
                Text("No quote yet")
                    .font(Theme.Fonts.detailLabel)
                    .foregroundStyle(.secondary)
            } else {
                HStack(alignment: .top, spacing: Theme.Space.detailColumns) {
                    column(left)
                    if !right.isEmpty { column(right) }
                }
            }
        }
        .padding(Theme.Space.detailPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Theme.Size.cardRadius, style: .continuous)
                .fill(Color.primary.opacity(Theme.Opacity.detailCard))
        )
    }

    /// Filled down the first column and then the second, so the band limits stay together and reading
    /// order is preserved — a left-to-right fill would put Ceiling next to Floor and split the pair that
    /// belongs together.
    private var left: [QuoteDetail.Row] {
        Array(rows.prefix((rows.count + 1) / 2))
    }

    private var right: [QuoteDetail.Row] {
        Array(rows.dropFirst((rows.count + 1) / 2))
    }

    private func column(_ rows: [QuoteDetail.Row]) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.detailRows) {
            ForEach(rows) { row in
                HStack(spacing: Theme.Space.detailLabel) {
                    Text(row.label)
                        .font(Theme.Fonts.detailLabel)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: Theme.Space.detailLabel)
                    Text(row.value)
                        .font(Theme.Fonts.detailValue)
                        .monospacedDigit()
                }
            }
        }
        // Equal halves, so the two columns' values line up down the card instead of each column hugging
        // its own longest number.
        .frame(maxWidth: .infinity)
    }
}
