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

    /// The domestic gold and FX boards — see `isDomesticBoardOpen`. Shop hours, not exchange hours: no
    /// call auction to wait for and no lunch break, because a jeweller does not close its board to eat.
    private static let domesticOpen = 8 * 60 + 30
    private static let domesticClose = 17 * 60

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

    /// The shape of an overnight week, which is what both the OTC gold market and ICE Futures US (the
    /// dollar index) keep: it opens on Sunday evening in New York, runs through every night, stops once a
    /// day for a maintenance break, and the last of those breaks is the close of the whole week. One type
    /// with two sets of edges rather than two hand-written predicates, because the only thing that differs
    /// between the venues is where the break falls.
    ///
    /// In ET, like the equity venues above, and for the same reason: the break is defined in the venue's
    /// own zone and moves with US daylight saving, so 17:00 ET is 04:00 ICT in summer and 05:00 in winter.
    private struct OvernightWeek {
        /// Sunday's reopen. Its own field rather than `breakEnd` reused, because ICE reopens for the week
        /// at 18:00 — an hour and a half before its own daily break ends.
        let sundayOpen: Int
        /// Where the daily break starts, which on a Friday is where the week ends.
        let breakStart: Int
        let breakEnd: Int
    }

    /// Both sets of edges come from a feed rather than from a venue's website, because what matters here is
    /// when the app can expect a new print, not when the exchange says it is matching (probed 2026-08-07):
    ///
    ///   • Gold's day rolls at 18:00 ET. TradingView's scanner reports the current trading day's start in
    ///     `time`, and it reads 18:00 New York — which is also exactly where COMEX's own minute bars resume
    ///     after their one hole a day. Those bars (`GC=F` at range=5d&interval=1m) stop at 16:59 and pick up
    ///     at 18:00 on every complete day in the window, a 61-minute gap, and the OTC market keeps the same
    ///     rollover. The scanner publishes no bars of its own, so this is corroboration rather than direct
    ///     measurement — but the two feeds agree on the boundary, which is the part that matters.
    ///   • `DX-Y.NYB` prints from Sunday 18:00 ET, stops at 18:04 and resumes between 19:31 and 19:45
    ///     depending on the day. Modelled as 18:00–19:30, a few minutes wide on both sides. The cost is at
    ///     most a quarter of an hour where the row counts as open before a new bar exists, so it can grey
    ///     out around 06:30 ICT; waiting for ICE's published 20:00 reopen instead would leave the price
    ///     standing for two hours, which is the worse of the two.
    private static let spotWeek = OvernightWeek(sundayOpen: 18 * 60,
                                                breakStart: 17 * 60,
                                                breakEnd: 18 * 60)
    private static let iceWeek = OvernightWeek(sundayOpen: 18 * 60,
                                               breakStart: 18 * 60,
                                               breakEnd: 19 * 60 + 30)

    /// Whether `market` is in a session at `date`. Crypto is always true — the venues run 24/7,
    /// including weekends, which is precisely why it can't share the equity gate.
    static func isOpen(_ market: Market, at date: Date = Date()) -> Bool {
        switch market {
        case .crypto:  return true
        case .vietnam: return isVietnamSessionOpen(at: date)
        case .world:
            // The union of the venues — and since spot gold and ICE trade overnight, that is now everything
            // but the weekend. Still the right answer to "does this market ever trade at this hour", and a
            // useless one for "is this row worth fetching": reading it that way would refetch the Dow, the
            // Nasdaq and the Nikkei every minute all night the moment a gold row joined the list. That is
            // why QuoteReader asks per symbol, via `isOpen(_:symbol:at:)`.
            return WorldExchange.allCases.contains { isOpen(exchange: $0, at: date) }
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
        case .spot:
            return isOpen(spotWeek, at: date)
        case .iceUS:
            return isOpen(iceWeek, at: date)
        }
    }

    /// Whether an overnight week is trading. Computed in New York's own components for the same
    /// reason as the equity venues, only more so: a Sunday 18:00 ET open lands on Monday at 05:00 ICT, so
    /// an ICT window would have to wrap onto the next weekday AND move with DST.
    private static func isOpen(_ week: OvernightWeek, at date: Date) -> Bool {
        guard let (weekday, minutes) = weekdayAndMinutes(at: date, in: newYork) else { return false }
        switch weekday {
        case 7:  return false                        // Saturday — the one full day these venues are shut
        case 1:  return minutes >= week.sundayOpen   // Sunday evening: the week starts
        case 6:  return minutes < week.breakStart    // Friday: the daily break IS the weekly close
        default: return !(minutes >= week.breakStart && minutes < week.breakEnd)
        }
    }

    /// Whether the venue that actually quotes `symbol` is trading.
    ///
    /// The same answer as `isOpen(market:)` for Vietnam and crypto, where a market IS one venue. `.world`
    /// is a bucket of venues, and the difference shows: it counts as open whenever any of them is trading.
    /// Without narrowing to the symbol's own exchange, every Dow row greyed out through the whole Tokyo
    /// session — six hours of a healthy feed looking broken.
    ///
    /// This is now the gate for FETCHING as well, and not only for staleness. The bucket's union used to
    /// have a real hole in it — between Tokyo's close and Wall Street's open — which made it a serviceable
    /// answer to "is anything here worth a request". Gold and the dollar index closed that hole: the union
    /// is true around the clock on a weekday, so asking it per market would poll every world row all night.
    static func isOpen(_ market: Market, symbol: String, at date: Date = Date()) -> Bool {
        if market == .world, let listing = WorldIndex.listing(for: symbol) {
            return isOpen(exchange: listing.exchange, at: date)
        }
        // `.vietnam` is no longer one venue either: a jeweller's board and a bank's rate sheet keep shop
        // hours, not HOSE's, and they do not stop for its lunch break.
        if market == .vietnam, DomesticIndex.isDomestic(symbol) {
            return isDomesticBoardOpen(at: date)
        }
        return isOpen(market, at: date)
    }

    /// When the domestic gold and FX boards can be expected to move: 08:30–17:00 ICT, Monday to Saturday.
    ///
    /// Retail hours rather than a measured feed window, and deliberately wider than either feed's actual
    /// publishing times. What IS measured is only the shape: PNJ's board carried `updateDate` 11:00:38 on a
    /// Saturday and nothing newer appeared on the Sunday, so Saturday counts and Sunday does not. The rest
    /// is the convention every shop and branch in the country keeps.
    ///
    /// Erring wide is the deliberate half. Being too generous costs a handful of requests for a number that
    /// has not changed; being too narrow means a price published at 16:45 goes unfetched until the next
    /// morning — or, on a Saturday, until Monday. That is the same trade this file already makes for public
    /// holidays, in the same direction.
    private static func isDomesticBoardOpen(at date: Date) -> Bool {
        guard let (weekday, minutes) = ictWeekdayAndMinutes(at: date) else { return false }
        guard weekday != 1 else { return false }              // Sunday: the boards stand still
        return minutes >= domesticOpen && minutes < domesticClose
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
            // Checked last on purpose: the overnight venues cover almost every hour, so putting them
            // first would answer for a Wall Street session as well and the line would stop telling anyone
            // anything. Reaching this means gold and the dollar index are the only world rows that can
            // still move.
            if isOpen(exchange: .spot, at: date) || isOpen(exchange: .iceUS, at: date) {
                return "Gold & FX open"
            }
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
