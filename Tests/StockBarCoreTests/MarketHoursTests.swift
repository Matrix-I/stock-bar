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

    @Test("The world market is open when any of its venues is, and closed between them")
    func worldIsTheUnion() {
        #expect(MarketHours.isOpen(.world, at: wednesday(8, 0)))               // Tokyo trading
        #expect(MarketHours.isOpen(.world, at: wednesday(22, 0)))              // Wall Street trading
        #expect(MarketHours.isOpen(.world, at: wednesday(16, 0)) == false)     // between the two
        #expect(MarketHours.isOpen(.world, at: wednesday(9, 30)) == false)     // Tokyo's lunch break
    }

    @Test("Staleness asks the symbol's own venue, not the whole bucket")
    func perSymbolVenue() {
        // 08:00 ICT: Tokyo is trading and New York closed hours ago. Asking the market alone answers "open"
        // for both, which greyed out every Dow row for the length of a Tokyo session.
        #expect(MarketHours.isOpen(.world, symbol: "NI225", at: wednesday(8, 0)))
        #expect(MarketHours.isOpen(.world, symbol: "DJI", at: wednesday(8, 0)) == false)
        #expect(MarketHours.isOpen(.world, symbol: "IXIC", at: wednesday(22, 0)))
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
        #expect(MarketHours.statusText(for: .world, at: wednesday(16, 0)) == "World markets closed")
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
}
