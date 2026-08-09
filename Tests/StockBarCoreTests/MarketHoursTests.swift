// MarketHoursTests.swift — the session gate that decides whether the app polls at all.
//
// This is the biggest saving in the app (it removes ~85% of requests) and also the most dangerous thing to
// get wrong in the quiet direction: a gate that wrongly reports "closed" during a session stops the prices
// updating with no error anywhere. The boundaries are therefore tested from both sides — a test that only
// checks 10:00 would pass against almost any wrong window.

import Testing
import Foundation
@testable import StockBarCore

@Suite("MarketHours")
struct MarketHoursTests {

    /// A wall-clock instant in Indochina Time, which is the only zone this gate reasons in.
    private func ict(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int) -> Date {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = MarketHours.ict
        return cal.date(from: DateComponents(year: year, month: month, day: day,
                                             hour: hour, minute: minute))!
    }

    // 2026-07-29 is a Wednesday; 2026-08-01 a Saturday and 2026-08-02 a Sunday.
    private func wednesday(_ hour: Int, _ minute: Int) -> Date { ict(2026, 7, 29, hour, minute) }

    @Test("The session opens at 09:00 and not a minute before")
    func openBoundary() {
        #expect(MarketHours.isOpen(.vietnam, at: wednesday(8, 59)) == false)
        #expect(MarketHours.isOpen(.vietnam, at: wednesday(9, 0)))
    }

    @Test("The last quarter hour is inside the session, and 15:00 is outside")
    func closeBoundary() {
        // 14:45–15:00 is put-through, and the closing price is only settled at the end of ATC — so polling
        // through 14:59 is what gets the correct close.
        #expect(MarketHours.isOpen(.vietnam, at: wednesday(14, 59)))
        #expect(MarketHours.isOpen(.vietnam, at: wednesday(15, 0)) == false)
    }

    @Test("The lunch break is a hole inside the session, 11:30 to 13:00")
    func lunchBreak() {
        #expect(MarketHours.isOpen(.vietnam, at: wednesday(11, 29)))
        #expect(MarketHours.isOpen(.vietnam, at: wednesday(11, 30)) == false)
        #expect(MarketHours.isOpen(.vietnam, at: wednesday(12, 59)) == false)
        #expect(MarketHours.isOpen(.vietnam, at: wednesday(13, 0)))
    }

    @Test("A weekend is closed at every hour")
    func weekend() {
        #expect(MarketHours.isOpen(.vietnam, at: ict(2026, 8, 1, 10, 0)) == false)  // Saturday
        #expect(MarketHours.isOpen(.vietnam, at: ict(2026, 8, 2, 10, 0)) == false)  // Sunday
    }

    @Test("Crypto never closes — not at night, not at the weekend")
    func cryptoIsAlwaysOpen() {
        #expect(MarketHours.isOpen(.crypto, at: wednesday(3, 0)))
        #expect(MarketHours.isOpen(.crypto, at: ict(2026, 8, 2, 3, 0)))
    }

    @Test("The status line names the reason, not just the state")
    func statusText() {
        // This line is the answer to "why isn't the price moving?", so each closed state has to be
        // distinguishable — "HOSE closed" alone would leave a lunch break looking like a broken feed.
        #expect(MarketHours.statusText(for: .vietnam, at: wednesday(10, 0)) == "HOSE open")
        #expect(MarketHours.statusText(for: .vietnam, at: wednesday(12, 0)) == "HOSE closed · lunch break")
        #expect(MarketHours.statusText(for: .vietnam, at: wednesday(7, 0)) == "HOSE opens 09:00 ICT")
        #expect(MarketHours.statusText(for: .vietnam, at: wednesday(16, 0)) == "HOSE closed · after hours")
        #expect(MarketHours.statusText(for: .vietnam, at: ict(2026, 8, 1, 10, 0)) == "HOSE closed · weekend")
        #expect(MarketHours.statusText(for: .crypto, at: wednesday(3, 0)) == "24/7")
    }

    @Test("A day's session has started from 09:00 until midnight, lunch break included")
    func sessionStarted() {
        // Not the same question as isOpen: this one asks whether the day has any movement to report yet, so
        // it must stay true through the hole at 12:00 and through the whole evening. A version of it written
        // as `isOpen` would let the change figure go flat over lunch and again after 15:00.
        #expect(MarketHours.hasSessionStarted(.vietnam, at: wednesday(8, 59)) == false)
        #expect(MarketHours.hasSessionStarted(.vietnam, at: wednesday(9, 0)))
        #expect(MarketHours.hasSessionStarted(.vietnam, at: wednesday(12, 0)))
        #expect(MarketHours.hasSessionStarted(.vietnam, at: wednesday(23, 59)))
        #expect(MarketHours.hasSessionStarted(.vietnam, at: wednesday(0, 1)) == false)
    }

    @Test("A weekend day never starts a session, at any hour")
    func sessionNeverStartsAtTheWeekend() {
        // Which is what keeps Friday's move from being reported as Saturday's.
        #expect(MarketHours.hasSessionStarted(.vietnam, at: ict(2026, 8, 1, 10, 0)) == false)
        #expect(MarketHours.hasSessionStarted(.vietnam, at: ict(2026, 8, 2, 20, 0)) == false)
        #expect(MarketHours.hasSessionStarted(.crypto, at: ict(2026, 8, 2, 20, 0)))
    }

    @Test("The session day turns at ICT midnight, not at the machine's own")
    func sessionDayBoundary() {
        // A machine in UTC is 7 hours behind: 23:30 ICT is still the previous UTC day, and a day boundary
        // computed in the local zone would move the reset by those 7 hours.
        #expect(MarketHours.isSameSessionDay(wednesday(9, 15), wednesday(23, 59)))
        #expect(MarketHours.isSameSessionDay(wednesday(23, 59), ict(2026, 7, 30, 0, 1)) == false)
    }

    // MARK: World venues

    // Expressed in ICT on purpose — that is the clock the app is read on, and the whole point of these
    // windows is that a New York session lands at a different ICT hour in July than in January.

    @Test("Wall Street's ICT hours move with US daylight saving")
    func newYorkFollowsDST() {
        // 09:30 in New York is 20:30 ICT in summer and 21:30 in winter. Hardcoding either offset — which is
        // what a fixed-offset gate would do — puts the window an hour out for half of every year.
        #expect(MarketHours.isOpen(exchange: .newYork, at: ict(2026, 7, 15, 20, 30)))       // Wed, EDT
        #expect(MarketHours.isOpen(exchange: .newYork, at: ict(2026, 1, 14, 20, 30)) == false) // Wed, EST
        #expect(MarketHours.isOpen(exchange: .newYork, at: ict(2026, 1, 14, 21, 30)))
    }

    @Test("Wall Street opens at 09:30 and the close is exclusive")
    func newYorkBoundaries() {
        #expect(MarketHours.isOpen(exchange: .newYork, at: ict(2026, 7, 15, 20, 29)) == false)
        #expect(MarketHours.isOpen(exchange: .newYork, at: ict(2026, 7, 16, 2, 59)))         // 15:59 EDT
        #expect(MarketHours.isOpen(exchange: .newYork, at: ict(2026, 7, 16, 3, 0)) == false) // 16:00 EDT
    }

    @Test("A Friday session in New York is still open on Saturday morning in Vietnam")
    func newYorkStraddlesTheICTWeek() {
        // 02:00 ICT on Saturday is 15:00 EDT on Friday: a live session. A gate that read the ICT weekday
        // would call it the weekend and stop polling an hour before the close.
        #expect(MarketHours.isOpen(exchange: .newYork, at: ict(2026, 8, 1, 2, 0)))
        #expect(MarketHours.isOpen(.world, at: ict(2026, 8, 1, 2, 0)))
        // Sunday 02:00 ICT is Saturday evening in New York, and nothing is trading.
        #expect(MarketHours.isOpen(exchange: .newYork, at: ict(2026, 8, 2, 2, 0)) == false)
    }

    @Test("Tokyo runs 09:00–15:30 JST with a lunch break, which is 07:00–13:30 ICT")
    func tokyoWindow() {
        #expect(MarketHours.isOpen(exchange: .tokyo, at: wednesday(6, 59)) == false)
        #expect(MarketHours.isOpen(exchange: .tokyo, at: wednesday(7, 0)))            // 09:00 JST
        #expect(MarketHours.isOpen(exchange: .tokyo, at: wednesday(9, 30)) == false)  // 11:30 JST, lunch
        #expect(MarketHours.isOpen(exchange: .tokyo, at: wednesday(10, 30)))          // 12:30 JST
        // 15:30, not 15:00: the TSE extended its session in November 2024 and the feed's own trading period
        // says 15:30. Half an hour of a real session would otherwise be treated as after hours.
        #expect(MarketHours.isOpen(exchange: .tokyo, at: wednesday(13, 29)))          // 15:29 JST
        #expect(MarketHours.isOpen(exchange: .tokyo, at: wednesday(13, 30)) == false) // 15:30 JST
    }

    @Test("Spot gold trades overnight, with one hole a day at 17:00 New York time")
    func spotGoldBreak() {
        // 16:00 ICT is 05:00 ET: the middle of the gold night session, when every equity venue is shut.
        #expect(MarketHours.isOpen(exchange: .spot, at: wednesday(16, 0)))
        // The break, both edges. 04:00 ICT on Thursday is 17:00 ET on Wednesday — COMEX's minute bars stop
        // at 16:59 and resume at 18:00 on every complete day in a 5-day window, and TradingView's scanner
        // puts the start of the spot trading day at the same 18:00, so the two feeds agree on the boundary.
        #expect(MarketHours.isOpen(exchange: .spot, at: ict(2026, 7, 30, 3, 59)))
        #expect(MarketHours.isOpen(exchange: .spot, at: ict(2026, 7, 30, 4, 0)) == false)
        #expect(MarketHours.isOpen(exchange: .spot, at: ict(2026, 7, 30, 4, 59)) == false)
        #expect(MarketHours.isOpen(exchange: .spot, at: ict(2026, 7, 30, 5, 0)))
    }

    @Test("The gold week ends on Friday afternoon and starts again on Sunday evening")
    func spotGoldWeek() {
        // Friday 17:00 ET is Saturday 04:00 ICT: the last daily break of the week never ends.
        #expect(MarketHours.isOpen(exchange: .spot, at: ict(2026, 8, 1, 3, 59)))       // Fri 16:59 ET
        #expect(MarketHours.isOpen(exchange: .spot, at: ict(2026, 8, 1, 4, 0)) == false)
        // And it stays shut for the rest of Friday: 07:00 ICT on Saturday is 20:00 ET on Friday, which a
        // week modelled as "every day has a break and then resumes" would report open again.
        #expect(MarketHours.isOpen(exchange: .spot, at: ict(2026, 8, 1, 7, 0)) == false)
        // Saturday in New York is the one full day off: 23:00 ICT on Saturday is 12:00 ET, still Saturday.
        #expect(MarketHours.isOpen(exchange: .spot, at: ict(2026, 8, 1, 23, 0)) == false)
        // And Sunday stays shut until the evening — 12:00 ICT on Sunday is only 01:00 ET on Sunday. Both
        // instants are needed: ICT and ET disagree about which day it is for eleven hours a day, so one
        // assertion cannot cover both weekend days.
        #expect(MarketHours.isOpen(exchange: .spot, at: ict(2026, 8, 2, 12, 0)) == false)
        // Sunday 18:00 ET is Monday 05:00 ICT, which is where the week begins.
        #expect(MarketHours.isOpen(exchange: .spot, at: ict(2026, 8, 3, 4, 59)) == false)
        #expect(MarketHours.isOpen(exchange: .spot, at: ict(2026, 8, 3, 5, 0)))
    }

    @Test("The overnight break moves with US daylight saving, like the equity venues")
    func overnightBreakFollowsDST() {
        // 17:00 ET is 04:00 ICT in summer and 05:00 in winter. A fixed offset would put this break an hour
        // out for half of every year — and a break in the wrong place is a row greying out at 4am, or a
        // fetch skipped while the market is live.
        #expect(MarketHours.isOpen(exchange: .spot, at: ict(2026, 1, 15, 4, 0)))         // 16:00 EST
        #expect(MarketHours.isOpen(exchange: .spot, at: ict(2026, 1, 15, 5, 0)) == false) // 17:00 EST
        #expect(MarketHours.isOpen(exchange: .spot, at: ict(2026, 1, 15, 6, 0)))         // 18:00 EST
    }

    @Test("ICE keeps its own break, an hour later and half an hour longer than gold's")
    func iceBreak() {
        // The two venues are NOT interchangeable, which is the whole reason they are separate cases: at
        // 17:30 ET gold has rolled over and the dollar index is still printing.
        #expect(MarketHours.isOpen(exchange: .iceUS, at: ict(2026, 7, 30, 4, 30)))
        #expect(MarketHours.isOpen(exchange: .spot, at: ict(2026, 7, 30, 4, 30)) == false)
        // ICE's own break: 18:00–19:30 ET, which is 05:00–06:30 ICT.
        #expect(MarketHours.isOpen(exchange: .iceUS, at: ict(2026, 7, 30, 4, 59)))
        #expect(MarketHours.isOpen(exchange: .iceUS, at: ict(2026, 7, 30, 5, 0)) == false)
        #expect(MarketHours.isOpen(exchange: .iceUS, at: ict(2026, 7, 30, 6, 29)) == false)
        #expect(MarketHours.isOpen(exchange: .iceUS, at: ict(2026, 7, 30, 6, 30)))
    }

    @Test("ICE reopens for the week before its daily break would have ended")
    func iceSundayOpenIsNotTheBreakEnd() {
        // Sunday 18:00 ET — Monday 05:00 ICT — is an hour and a half before 19:30, so a week modelled with
        // one edge for both would report the dollar index closed for the first 90 minutes of every week.
        #expect(MarketHours.isOpen(exchange: .iceUS, at: ict(2026, 8, 3, 5, 0)))
        #expect(MarketHours.isOpen(exchange: .iceUS, at: ict(2026, 8, 3, 4, 59)) == false)
        // And Friday's close is its break start, an hour after gold's: Saturday 05:00 ICT is Friday 18:00 ET.
        #expect(MarketHours.isOpen(exchange: .iceUS, at: ict(2026, 8, 1, 4, 59)))
        #expect(MarketHours.isOpen(exchange: .iceUS, at: ict(2026, 8, 1, 5, 0)) == false)
        #expect(MarketHours.isOpen(exchange: .iceUS, at: ict(2026, 8, 1, 7, 0)) == false)   // Fri 20:00 ET
    }

    @Test("The world market is open when any of its venues is, which is now all but the weekend")
    func worldIsTheUnion() {
        #expect(MarketHours.isOpen(.world, at: wednesday(8, 0)))               // Tokyo trading
        #expect(MarketHours.isOpen(.world, at: wednesday(22, 0)))              // Wall Street trading
        // 16:00 ICT is 05:00 ET: both equity venues are shut and the overnight ones are not. The union used
        // to be false here, which is what made it a serviceable "is anything worth fetching" — it no longer
        // is, and QuoteReader asks per symbol instead.
        #expect(MarketHours.isOpen(.world, at: wednesday(16, 0)))
        #expect(MarketHours.isOpen(.world, at: wednesday(9, 30)))              // Tokyo's lunch break
        // The weekend is the only hole left: Saturday 12:00 ICT is Saturday 01:00 ET.
        #expect(MarketHours.isOpen(.world, at: ict(2026, 8, 1, 12, 0)) == false)
    }

    @Test("Staleness and the fetch gate ask the symbol's own venue, not the whole bucket")
    func perSymbolVenue() {
        // 08:00 ICT: Tokyo is trading and New York closed hours ago. Asking the market alone answers "open"
        // for both, which greyed out every Dow row for the length of a Tokyo session.
        #expect(MarketHours.isOpen(.world, symbol: "NI225", at: wednesday(8, 0)))
        #expect(MarketHours.isOpen(.world, symbol: "DJI", at: wednesday(8, 0)) == false)
        #expect(MarketHours.isOpen(.world, symbol: "IXIC", at: wednesday(22, 0)))
        // 16:00 ICT is the hour that matters now: gold is trading, the dollar index is trading, and the
        // three equity indices are not. Answering per market would have all five refetched every minute.
        #expect(MarketHours.isOpen(.world, symbol: "GOLD", at: wednesday(16, 0)))
        #expect(MarketHours.isOpen(.world, symbol: "DXY", at: wednesday(16, 0)))
        #expect(MarketHours.isOpen(.world, symbol: "DJI", at: wednesday(16, 0)) == false)
        #expect(MarketHours.isOpen(.world, symbol: "NI225", at: wednesday(16, 0)) == false)
        // An alias narrows to the same venue as its canonical name, since `listing` accepts both.
        #expect(MarketHours.isOpen(.world, symbol: "XAU", at: wednesday(16, 0)))
        // A market that is one venue answers exactly as it did before.
        #expect(MarketHours.isOpen(.vietnam, symbol: "VCB", at: wednesday(10, 0)))
        #expect(MarketHours.isOpen(.crypto, symbol: "BTCUSDT", at: wednesday(3, 0)))
        // An unlisted world symbol has no venue to narrow to, so it falls back to the bucket.
        #expect(MarketHours.isOpen(.world, symbol: "AAPL", at: wednesday(8, 0)))
    }

    @Test("The world status line names the venue that is trading")
    func worldStatusText() {
        #expect(MarketHours.statusText(for: .world, at: wednesday(22, 0)) == "Wall St open")
        #expect(MarketHours.statusText(for: .world, at: wednesday(8, 0)) == "Tokyo open")
        // The overnight venues are checked last: naming them while Wall Street is open would replace the
        // more useful line with one that is true almost all the time.
        #expect(MarketHours.statusText(for: .world, at: wednesday(16, 0)) == "Gold & FX open")
        #expect(MarketHours.statusText(for: .world, at: ict(2026, 8, 1, 12, 0)) == "World markets closed")
    }

    @Test("A world index is never waiting for an ICT day to start")
    func worldNeverPendsOnTheICTDay() {
        // Its session straddles ICT midnight, so the VN reset must not reach it — see
        // Quote.rebasedForPendingSession.
        #expect(MarketHours.hasSessionStarted(.world, at: wednesday(0, 30)))
        #expect(MarketHours.hasSessionStarted(.world, at: ict(2026, 8, 2, 3, 0)))
    }

    @Test("Indochina Time is a fixed +07:00, with no DST to track")
    func fixedOffset() {
        // Vietnam has observed no DST since 1975. A fixed offset is what keeps the gate correct even on a
        // machine with an incomplete time-zone database.
        #expect(MarketHours.ict.secondsFromGMT() == 7 * 3600)
    }

    @Test("The trading day turns at ICT midnight, wherever the machine thinks it is")
    func tradingDayTurnsInVietnam() {
        // Three caches expire on this one answer: the fundamentals figures, the daily bars behind a
        // reference close, and the breadth constituent list. Each used to compute it for itself.
        let lateEvening = ict(2026, 8, 5, 23, 59)
        let justAfter = ict(2026, 8, 6, 0, 1)
        #expect(MarketHours.tradingDay(at: lateEvening) + 1 == MarketHours.tradingDay(at: justAfter))
        // A whole ICT day is one number, from its first minute to its last.
        #expect(MarketHours.tradingDay(at: ict(2026, 8, 6, 0, 0))
                == MarketHours.tradingDay(at: ict(2026, 8, 6, 23, 58)))

        // Pinned to a literal, so the boundary is fixed by this test rather than by whatever the
        // implementation currently computes. 2026-08-06 00:00 ICT is 2026-08-05 17:00 UTC, epoch
        // 1,785,913,200, which floors to day 20,670.
        #expect(MarketHours.tradingDay(at: ict(2026, 8, 6, 0, 0)) == 20_670)
        #expect(MarketHours.tradingDay(at: ict(2026, 8, 5, 23, 59)) == 20_669)

        // One thing this suite CANNOT check: that the zone is ICT rather than the machine's. This machine
        // runs at +07:00, so `ictCalendar` and the system calendar are the same function here and a mutant
        // swapping one for the other survives — correctly, and not for want of an assertion. What keeps it
        // right is that `tradingDay` names its zone; what would catch it is running the suite abroad.
    }
}
