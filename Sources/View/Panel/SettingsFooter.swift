// SettingsFooter.swift — the block below the last divider: session state, the last fetch, three
// switches, and the two things you'd close the panel to do.
//
// Its type is a fifth smaller than the rows above it (Theme.settingsScale) because this is chrome you
// set once rather than data you read.

import SwiftUI

struct SettingsFooter: View {
    @ObservedObject var reader: QuoteReader
    /// @ObservedObject, not a plain `let`: the automatic-check value lives inside SPUUpdater, so without
    /// observing this the switch would write the new value and redraw from the old one.
    @ObservedObject var updater: Updater
    /// Closes the popover and starts a user-initiated Sparkle check; supplied by AppDelegate. The popover
    /// has to close first: it is `.applicationDefined`, so it would otherwise stay open on top of the
    /// update window it just spawned.
    let checkForUpdates: () -> Void
    let quitAction: () -> Void

    @State private var launchAtLogin = LoginItem.isEnabled
    /// AppStorage rather than @State: AppDelegate reads this same key out of UserDefaults to decide what
    /// to draw in the menu bar, and picks the change up through its didChangeNotification observer.
    @AppStorage("showChangeInMenuBar") private var showChangeInMenuBar = true

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.stack) {
            sessionRow

            if let err = reader.lastError {
                Text(err)
                    .font(Theme.Fonts.settingsStatus)
                    .foregroundStyle(.orange)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            switchRow("Show change % in the menu bar", isOn: $showChangeInMenuBar)

            // The @State mirror is what makes the switch move: LoginItem reads its state from
            // SMAppService, which publishes nothing, so a binding straight onto it would flip the login
            // item and then redraw from the old value.
            switchRow("Launch at login", isOn: Binding(
                get: { launchAtLogin },
                set: { launchAtLogin = $0; LoginItem.setEnabled($0) }
            ))

            // Sparkle persists this itself, so it is a direct binding onto the updater rather than an
            // @AppStorage key of ours that would have to be kept in step with Sparkle's own default.
            switchRow("Automatically check for updates", isOn: Binding(
                get: { updater.automaticallyChecks },
                set: { updater.automaticallyChecks = $0 }
            ))

            Button(action: checkForUpdates) {
                Text("Check for updates…").font(Theme.Fonts.settingsLabel)
            }
            .buttonStyle(.link)

            HStack {
                Spacer()
                Button("Quit", action: quitAction)
            }
        }
    }

    /// The answer to "why isn't the price moving?" — without it a closed market is indistinguishable from
    /// a broken feed.
    private var sessionRow: some View {
        HStack(spacing: Theme.Space.control) {
            Circle()
                .fill(MarketHours.isOpen(.vietnam) ? Color.green : Color.secondary)
                .frame(width: Theme.Size.sessionDot, height: Theme.Size.sessionDot)
            Text(MarketHours.statusText(for: .vietnam))
                .font(Theme.Fonts.settingsStatus)
                .foregroundStyle(.secondary)
            Spacer()
            if let at = reader.lastSuccessAt {
                Text(PriceFormat.asOf(at))
                    .font(Theme.Fonts.settingsStatus)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// A settings row: label on the left, switch on the right. Same shape as stats-bar's Control Center
    /// so the two apps' panels read alike — and a switch states its on/off position at a glance, which a
    /// checkbox in a dark popover does less well.
    private func switchRow(_ label: String, isOn: Binding<Bool>) -> some View {
        HStack {
            Text(label).font(Theme.Fonts.settingsLabel)
            Spacer(minLength: Theme.Space.switchGap)
            Toggle(label, isOn: isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .tint(.green)
        }
    }
}
