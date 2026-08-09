// QuoteDetailCard.swift — the card that opens off a row while the pointer rests on it.
//
// It replaced the row's `.help()` tooltip. AppKit holds a tooltip back for one to two seconds and then
// draws it in its own window, wherever the pointer happens to be; this appears at once, in the panel,
// against the row it describes. What it says is QuoteDetail's decision and where it goes is
// DetailCardOverlay's — this file only lays it out and gives it its edge.
//
// Two columns rather than one because a Vietnamese equity has seven things worth saying, and seven stacked
// rows would be taller than the quote row they annotate.

import SwiftUI

struct QuoteDetailCard: View {
    let rows: [QuoteDetail.Row]

    var body: some View {
        Group {
            if rows.isEmpty {
                // A pinned symbol whose fetch has never succeeded. Saying so is the point of clicking it.
                Text("No quote yet")
                    .font(Theme.Fonts.detailLabel)
                    .foregroundStyle(CardStyle.label)
            } else {
                HStack(alignment: .top, spacing: Theme.Space.detailColumns) {
                    column(left)
                    if !right.isEmpty { column(right) }
                }
            }
        }
        .padding(Theme.Space.detailPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(backing)
    }

    /// The card floats over the rows below it, so its backing has to do two things the old in-flow wash
    /// didn't: hide what it covers, and look like it is on top.
    ///
    /// Opaque, because at 7% of the panel's own colour the prices underneath read straight through it, and
    /// two numbers in the same place is the one thing a price panel must never do. Not a `Material` either:
    /// inside an already-vibrant popover a material blurs the desktop behind the window rather than the rows
    /// behind the card, which is the wrong backdrop and no help at all.
    ///
    /// The fill is the app's own background colour, so the hairline and the shadow are what make this a card
    /// at all rather than a gap in the list — see CardStyle.
    private var backing: some View {
        RoundedRectangle(cornerRadius: Theme.Size.cardRadius, style: .continuous)
            .fill(CardStyle.surface)
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Size.cardRadius, style: .continuous)
                    .strokeBorder(CardStyle.border, lineWidth: Theme.Size.cardBorder)
            )
            .shadow(color: CardStyle.shadow,
                    radius: Theme.Size.cardShadow,
                    y: Theme.Space.cardShadowY)
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
                        .foregroundStyle(CardStyle.label)
                    Spacer(minLength: Theme.Space.detailLabel)
                    Text(row.value)
                        .font(Theme.Fonts.detailValue)
                        .monospacedDigit()
                        .foregroundStyle(CardStyle.value)
                        // Shrink before wrapping: a crypto range ("64,730.08–65,192.54") is the widest
                        // value a card can carry, and wrapped onto a second line it made that one row
                        // double-height, knocking every row below it out of line with the other column.
                        // A slightly smaller number is legible; two misaligned columns are not.
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
            }
        }
        // Equal halves, so the two columns' values line up down the card instead of each column hugging
        // its own longest number.
        .frame(maxWidth: .infinity)
    }
}
