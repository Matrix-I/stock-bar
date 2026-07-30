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
//
// It also owns the DAY boundary, which is a different question from the session one: `isOpen` decides
// whether to fetch, while `hasSessionStarted` and `isSameSessionDay` decide whether a reading is still
// today's news. Both live here because both are the same clock in the same zone, and having two files
// spell out "09:00 ICT" is how they eventually disagree.

import Foundation

enum MarketHours {

    /// Indochina Time. Fixed offset rather than the "Asia/Ho_Chi_Minh" identifier so the check cannot
    /// be thrown off if the machine has an incomplete time-zone database; Vietnam has observed no DST
    /// since 1975, so a fixed +07:00 is correct indefinitely.
    static let ict = TimeZone(secondsFromGMT: 7 * 3600)!

    /// The session's edges as minutes past ICT midnight. Named once because three functions below read
    /// them and a session boundary written out twice is one that gets moved in one place only.
    private static let open = 9 * 60
    private static let close = 15 * 60
    private static let lunchStart = 11 * 60 + 30
    private static let lunchEnd = 13 * 60

    private static var ictCalendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = ict
        return cal
    }

    /// New York and Tokyo, from the system time-zone database rather than as fixed offsets — the opposite
    /// choice to `ict` above, and for the opposite reason. Vietnam has no DST, so arithmetic is exactly
    /// right there and a missing database entry cannot hurt it. Eastern Time moves an hour twice a year, so
    /// NO fixed offset is right all year: 09:30 in New York is 20:30 ICT in summer and 21:30 in winter, and
    /// hardcoding either one puts the gate an hour out for half the year. The fallbacks are the standard
    /// (winter) offsets, which only matter on a machine whose database has no entry at all.
    private static let newYork = TimeZone(identifier: "America/New_York") ?? TimeZone(secondsFromGMT: -5 * 3600)!
    private static let tokyo = TimeZone(identifier: "Asia/Tokyo") ?? TimeZone(secondsFromGMT: 9 * 3600)!

    /// Wall Street: one continuous session, 09:30–16:00 ET, no lunch break.
    private static let nyOpen = 9 * 60 + 30
    private static let nyClose = 16 * 60
    /// Tokyo: 09:00–11:30 and 12:30–15:30 JST. The close is 15:30 and not 15:00 — the TSE extended the
    /// session in November 2024 and added the 15:25–15:30 closing auction; the feed's own
    /// `currentTradingPeriod` says 15:30, which is what this was checked against.
    private static let tokyoOpen = 9 * 60
    private static let tokyoLunchStart = 11 * 60 + 30
    private static let tokyoLunchEnd = 12 * 60 + 30
    private static let tokyoClose = 15 * 60 + 30

    /// Whether `market` is in a session at `date`. Crypto is always true — the venues run 24/7,
    /// including weekends, which is precisely why it can't share the equity gate.
    static func isOpen(_ market: Market, at date: Date = Date()) -> Bool {
        switch market {
        case .crypto:  return true
        case .vietnam: return isVietnamSessionOpen(at: date)
        case .world:   return WorldExchange.allCases.contains { isOpen(exchange: $0, at: date) }
        }
    }

    /// Whether one world venue is trading. Computed in the venue's OWN zone rather than by converting its
    /// hours into ICT: a New York session runs 20:30–03:00 ICT, so an ICT window has to wrap past midnight
    /// onto the next weekday, and that wrap plus DST is two chances to be an hour or a day out. In local
    /// components there is no wrap and no DST arithmetic — 09:30 is 09:30 in New York in both halves of the
    /// year.
    static func isOpen(exchange: WorldExchange, at date: Date = Date()) -> Bool {
        switch exchange {
        case .newYork:
            guard let (weekday, minutes) = weekdayAndMinutes(at: date, in: newYork) else { return false }
            guard weekday != 1, weekday != 7 else { return false }
            return minutes >= nyOpen && minutes < nyClose
        case .tokyo:
            guard let (weekday, minutes) = weekdayAndMinutes(at: date, in: tokyo) else { return false }
            guard weekday != 1, weekday != 7 else { return false }
            guard minutes >= tokyoOpen, minutes < tokyoClose else { return false }
            return !(minutes >= tokyoLunchStart && minutes < tokyoLunchEnd)
        }
    }

    /// Whether the venue that actually quotes `symbol` is trading.
    ///
    /// The same answer as `isOpen(market:)` for Vietnam and crypto, where a market IS one venue. `.world`
    /// is a bucket of venues, and the difference shows: it counts as open whenever any of them is trading,
    /// which is the right rule for "is this worth polling" and the wrong one for "should this row look
    /// stale". Without narrowing to the symbol's own exchange, every Dow row greyed out through the whole
    /// Tokyo session — six hours of a healthy feed looking broken.
    static func isOpen(_ market: Market, symbol: String, at date: Date = Date()) -> Bool {
        guard market == .world, let listing = WorldIndex.listing(for: symbol) else {
            return isOpen(market, at: date)
        }
        return isOpen(exchange: listing.exchange, at: date)
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
        guard let (weekday, minutes) = ictWeekdayAndMinutes(at: date) else { return false }

        // Calendar weekday: 1 = Sunday … 7 = Saturday.
        guard weekday != 1, weekday != 7 else { return false }
        guard minutes >= open, minutes < close else { return false }
        return !(minutes >= lunchStart && minutes < lunchEnd)
    }

    /// Whether the ICT day `date` falls in has reached its trading session yet.
    ///
    /// Deliberately NOT `isOpen`. It stays true from 09:00 right through the lunch break and the whole
    /// evening, because the question it answers is "is there a session's worth of movement to report on
    /// this day" — which is what separates a change figure that is today's news from one left over from
    /// the last session. It is false for every hour of a weekend, since that day never gets a session.
    ///
    /// Crypto is always true: the venues never close, so a crypto reading is never waiting for one.
    static func hasSessionStarted(_ market: Market, at date: Date = Date()) -> Bool {
        switch market {
        case .crypto:
            return true
        case .world:
            // Not "the session has begun" so much as "there is no ICT day to wait for". A Wall Street
            // session straddles ICT midnight — it opens at 20:30 and closes at 03:00 the next ICT day — and
            // Yahoo rolls each index's previous close with its own venue's day, so the reset this predicate
            // exists for (see Quote.rebasedForPendingSession) has nothing to do here. Answering false would
            // flatten a Dow quote every ICT midnight, in the middle of the session it belongs to.
            return true
        case .vietnam:
            guard let (weekday, minutes) = ictWeekdayAndMinutes(at: date) else { return false }
            guard weekday != 1, weekday != 7 else { return false }
            return minutes >= open
        }
    }

    /// Whether two instants fall on the same ICT calendar day.
    ///
    /// Midnight ICT is where the boards' "today" begins: the reference price, the session volume and the
    /// permitted band are all quantities of one calendar day, so a reading from before that line is not a
    /// reading about the day it is being looked at on.
    static func isSameSessionDay(_ a: Date, _ b: Date) -> Bool {
        ictCalendar.isDate(a, inSameDayAs: b)
    }

    private static func ictWeekdayAndMinutes(at date: Date) -> (weekday: Int, minutes: Int)? {
        weekdayAndMinutes(at: date, in: ict)
    }

    /// `date` as a local weekday (1 = Sunday … 7 = Saturday) and minutes past local midnight, in `zone`.
    private static func weekdayAndMinutes(at date: Date, in zone: TimeZone) -> (weekday: Int, minutes: Int)? {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = zone
        let c = cal.dateComponents([.weekday, .hour, .minute], from: date)
        guard let weekday = c.weekday, let hour = c.hour, let minute = c.minute else { return nil }
        return (weekday, hour * 60 + minute)
    }

    /// A one-line description of the current session state, shown at the bottom of the popover so the
    /// user can tell "the price hasn't moved" from "the app has stopped fetching".
    static func statusText(for market: Market, at date: Date = Date()) -> String {
        switch market {
        case .crypto:
            return "24/7"
        case .world:
            // Named by venue, because "world open" would be true for most of the day and answer nothing.
            // No ICT clock time for the next open: Wall Street's lands at 20:30 or 21:30 depending on the
            // month, and a line that is wrong for half the year is worse than one that omits it.
            if isOpen(exchange: .newYork, at: date) { return "Wall St open" }
            if isOpen(exchange: .tokyo, at: date) { return "Tokyo open" }
            return "World markets closed"
        case .vietnam:
            if isVietnamSessionOpen(at: date) { return "HOSE open" }
            guard let (weekday, minutes) = ictWeekdayAndMinutes(at: date) else { return "HOSE closed" }
            if weekday == 1 || weekday == 7 { return "HOSE closed · weekend" }
            if minutes >= lunchStart && minutes < lunchEnd { return "HOSE closed · lunch break" }
            if minutes < open { return "HOSE opens 09:00 ICT" }
            return "HOSE closed · after hours"
        }
    }
}
