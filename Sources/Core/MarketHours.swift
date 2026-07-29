// MarketHours.swift — decides whether an exchange is trading right now, so the app can drop to a slow
// cadence outside session hours instead of hammering an endpoint all night for a number that cannot
// change. This is the single biggest saving available: HOSE trades roughly 5 hours a weekday, so
// gating on it cuts request volume by about 85% and stops the laptop waking to poll a closed market.
//
// Session structure (HOSE / HNX / UPCOM, Indochina Time = UTC+7, no DST):
//   09:00–09:15  ATO       — opening call auction (HOSE; HNX opens straight into continuous trading)
//   09:15–11:30  continuous
//   11:30–13:00  lunch break — the boards are frozen; prices do not move
//   13:00–14:30  continuous
//   14:30–14:45  ATC       — closing call auction
//   14:45–15:00  put-through / negotiated deals; the matched price no longer moves
//
// We treat 09:00–15:00 as "open" with a hole at 11:30–13:00. The final 15 minutes are included on
// purpose: the closing price is only settled at the end of ATC and the board is still being updated,
// so polling through 15:00 is what gets the correct close.

import Foundation

enum MarketHours {

    /// Indochina Time. Fixed offset rather than the "Asia/Ho_Chi_Minh" identifier so the check cannot
    /// be thrown off if the machine has an incomplete time-zone database; Vietnam has observed no DST
    /// since 1975, so a fixed +07:00 is correct indefinitely.
    static let ict = TimeZone(secondsFromGMT: 7 * 3600)!

    /// Whether `market` is in a session at `date`. Crypto is always true — the venues run 24/7,
    /// including weekends, which is precisely why it can't share the equity gate.
    static func isOpen(_ market: Market, at date: Date = Date()) -> Bool {
        switch market {
        case .crypto:  return true
        case .vietnam: return isVietnamSessionOpen(at: date)
        }
    }

    /// True during a HOSE/HNX trading session: a weekday, inside 09:00–15:00 ICT, and not in the
    /// 11:30–13:00 lunch break.
    ///
    /// Public holidays are deliberately NOT modelled. A hardcoded calendar goes stale every year and
    /// would then wrongly suppress polling on a day the market is actually open — a silent failure
    /// that looks like a broken app. Polling a closed exchange, by contrast, is harmless: the endpoint
    /// returns the previous close and the app shows it correctly. So the failure mode is chosen
    /// deliberately: waste a few requests on Tết rather than show a stale price on a trading day.
    private static func isVietnamSessionOpen(at date: Date) -> Bool {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = ict
        let c = cal.dateComponents([.weekday, .hour, .minute], from: date)
        guard let weekday = c.weekday, let hour = c.hour, let minute = c.minute else { return false }

        // Calendar weekday: 1 = Sunday … 7 = Saturday.
        guard weekday != 1, weekday != 7 else { return false }

        let minutes = hour * 60 + minute
        let open = 9 * 60, close = 15 * 60
        let lunchStart = 11 * 60 + 30, lunchEnd = 13 * 60

        guard minutes >= open, minutes < close else { return false }
        return !(minutes >= lunchStart && minutes < lunchEnd)
    }

    /// A one-line description of the current session state, shown at the bottom of the popover so the
    /// user can tell "the price hasn't moved" from "the app has stopped fetching".
    static func statusText(for market: Market, at date: Date = Date()) -> String {
        switch market {
        case .crypto:
            return "24/7"
        case .vietnam:
            if isVietnamSessionOpen(at: date) { return "HOSE open" }
            var cal = Calendar(identifier: .gregorian)
            cal.timeZone = ict
            let c = cal.dateComponents([.weekday, .hour, .minute], from: date)
            guard let weekday = c.weekday, let hour = c.hour, let minute = c.minute else { return "HOSE closed" }
            if weekday == 1 || weekday == 7 { return "HOSE closed · weekend" }
            let minutes = hour * 60 + minute
            if minutes >= 11 * 60 + 30 && minutes < 13 * 60 { return "HOSE closed · lunch break" }
            if minutes < 9 * 60 { return "HOSE opens 09:00 ICT" }
            return "HOSE closed · after hours"
        }
    }
}
