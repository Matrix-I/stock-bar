// PanelHeader.swift — the panel's title row: what this is, which build it is, and the two buttons that
// act on the whole list.

import SwiftUI

struct PanelHeader: View {
    let isFetching: Bool
    @Binding var editing: Bool
    let onRefresh: () -> Void

    var body: some View {
        HStack {
            Text("StockBar").font(Theme.Fonts.panelTitle)
            // A snapshot build says so; a released one shows the bare version. Without this the only
            // way to tell which build is running is to inspect Info.plist by hand.
            Text(AppInfo.version)
                .font(Theme.Fonts.version)
                .foregroundStyle(AppInfo.isSnapshot ? Color(nsColor: .systemOrange) : .secondary)
                .help(AppInfo.isSnapshot ? "Unreleased development build" : "Released build")
            if isFetching {
                ProgressView()
                    .controlSize(.small)
                    .scaleEffect(Theme.spinnerScale)
                    .frame(width: Theme.Size.spinner, height: Theme.Size.spinner)
            }
            Spacer()
            iconButton(editing ? "checkmark" : "square.and.pencil",
                       help: editing ? "Done" : "Edit the watchlist") { editing.toggle() }
            iconButton("arrow.clockwise", help: "Refresh now", action: onRefresh)
        }
    }

    private func iconButton(_ symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(Theme.Fonts.toolbarIcon)
        }
        .buttonStyle(.plain)
        .help(help)
    }
}
