// AlertNotifier.swift — posts a macOS notification when a price alert fires.
//
// The whole of the decision is in Core/PriceAlert.swift; this file only carries the verdict to the system,
// which is why it is here beside LoginItem rather than in Store. Nothing about it is testable — a
// notification either appears on somebody's screen or it does not — so there is deliberately no logic in it
// to test.
//
// TWO THINGS ABOUT UNUserNotificationCenter ON A HAND-BUILT BUNDLE:
//
//   • It requires a bundle identifier and raises an ObjC exception without one — not a Swift error, so it
//     cannot be caught. `Tools/probe.swift` and `Tools/uisnap.sh` compile these same sources into a bare
//     executable with no bundle at all, and both build a QuoteReader, so an unguarded `.current()` would
//     take down the two tools this project verifies itself with. Hence `center`, which returns nil rather
//     than reaching for it. Sparkle already fails the same way in those tools and says so in the log.
//   • Authorisation is asked for on the first alert, not at launch. A menu-bar ticker that demands
//     notification permission before it has anything to notify about gets refused, and the refusal is
//     remembered; asking at the moment the user creates their first alert asks a question they have just
//     shown they want the answer to.

import Foundation
import UserNotifications

@MainActor
final class AlertNotifier {

    /// nil in a bundle-less build — see the header. Every call site treats that as "no notifications here"
    /// rather than as an error, because it only ever happens in the two dev tools.
    private var center: UNUserNotificationCenter? {
        guard Bundle.main.bundleIdentifier != nil else { return nil }
        return .current()
    }

    /// Ask for permission, if it has not been asked for already. Called when an alert is created.
    ///
    /// The result is deliberately ignored. A denial is not an error to report — the alert is still stored,
    /// still evaluated, and starts working the moment permission is granted in System Settings — and a
    /// modal complaining about it would be a second interruption on top of the one just refused.
    func requestAuthorizationIfNeeded() {
        guard let center else { return }
        center.requestAuthorization(options: [.alert, .sound]) { _, error in
            if let error { NSLog("StockBar: notification authorisation failed — \(error.localizedDescription)") }
        }
    }

    func post(_ firing: AlertEngine.Firing) {
        guard let center else { return }
        let content = UNMutableNotificationContent()
        content.title = firing.title
        content.body = firing.body
        content.sound = .default

        // Identified by the row and the threshold rather than by a fresh UUID, so a re-fire of the SAME
        // alert replaces its predecessor in Notification Centre instead of stacking another copy under it.
        // The arming rule upstairs already makes that rare; this makes the rare case tidy.
        let id = "\(firing.id)|\(firing.alert.direction.rawValue)|\(firing.alert.threshold)"
        // nil trigger means deliver now.
        center.add(UNNotificationRequest(identifier: id, content: content, trigger: nil)) { error in
            if let error { NSLog("StockBar: could not post an alert — \(error.localizedDescription)") }
        }
    }
}
