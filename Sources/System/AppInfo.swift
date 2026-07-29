// AppInfo.swift — where the running build says which build it is.
//
// The version is not written here. It lives in the VERSION file at the repo root, which build_app.sh
// stamps into Info.plist and release.sh is the only thing that edits. Reading it back out of the
// bundle at runtime means there is exactly one place it can be wrong.

import Foundation

enum AppInfo {
    /// CFBundleShortVersionString, e.g. "1.0.0-SNAPSHOT" during development and "1.0.0" for a release.
    /// The fallback matters: the command-line probe links this file but is not a bundle, so there is no
    /// Info.plist to read and an unwrapped lookup would crash it.
    static var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
    }

    /// True while this is an unreleased build. Surfaced in the UI so a snapshot is never mistaken for
    /// the tagged version someone downloaded — the whole point of keeping the suffix.
    static var isSnapshot: Bool { version.contains("SNAPSHOT") || version == "dev" }
}
