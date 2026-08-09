// PriceAlertTests.swift — the arming rules, walked through price series.
//
// These carry more weight than most tests here because the failure they guard against costs more than a
// wrong number on a panel: an alert that fires on every tick spends the app's notification permission, and
// the user who revokes it does not come back. The bug is also nearly unobservable by hand — telling "fires
// once" from "fires every minute" takes an hour of watching a real price sit on a real threshold.

import Testing
import Foundation
@testable import StockBarCore

@Suite("PriceAlert")
struct PriceAlertTests {

    @Test("An alert fires on the crossing and then goes quiet")
    func firesOnce() {
        var alert = PriceAlert(direction: .above, threshold: 60_000, currentPrice: 59_000)
        #expect(alert.isArmed)

        // Below the line: nothing.
        var step = alert.advanced(to: 59_500)
        #expect(!step.fires)
        alert = step.alert

        // The crossing.
        step = alert.advanced(to: 60_000)
        #expect(step.fires)
        alert = step.alert
        #expect(!alert.isArmed)

        // Every tick after it, however far past the threshold, says nothing more. This is the whole test:
        // an alert that kept firing here would post a notification a minute for the rest of the session.
        for price in [60_100.0, 61_000, 60_000, 65_000] {
            step = alert.advanced(to: price)
            #expect(!step.fires)
            alert = step.alert
        }
    }

    @Test("A price resting on the threshold cannot pump the alert")
    func hysteresis() {
        var alert = PriceAlert(direction: .above, threshold: 60_000, currentPrice: 59_000)
        alert = alert.advanced(to: 60_010).alert     // fires, disarms

        // Dipping a hair under the line does NOT rearm — this is the case that would otherwise fire again
        // on the very next tick, and then again, for as long as the price hovered.
        for price in [59_990.0, 60_020, 59_800, 60_100] {
            let step = alert.advanced(to: price)
            #expect(!step.fires)
            #expect(!step.alert.isArmed)
            alert = step.alert
        }

        // Clear of the margin (0.5% of 60,000 is 300), so it is live again — and only then can it fire.
        alert = alert.advanced(to: 59_600).alert
        #expect(alert.isArmed)
        let again = alert.advanced(to: 60_050)
        #expect(again.fires)
    }

    @Test("An alert set on a price that has already crossed waits for the next one")
    func startsDisarmedWhenAlreadyTrue() {
        // Someone watching gold at 4,341 who asks to be told when it passes 4,300 means the NEXT time, not
        // the number they are looking at while typing.
        let above = PriceAlert(direction: .above, threshold: 4_300, currentPrice: 4_341)
        #expect(!above.isArmed)
        #expect(!above.advanced(to: 4_350).fires)

        // It arms once the price is clear below the line, and fires on the crossing after that.
        let armed = above.advanced(to: 4_200).alert
        #expect(armed.isArmed)
        #expect(armed.advanced(to: 4_305).fires)

        // The mirror case, and the ordinary one: set below a price that is above it.
        let below = PriceAlert(direction: .below, threshold: 4_300, currentPrice: 4_341)
        #expect(below.isArmed)
        #expect(below.advanced(to: 4_299).fires)
    }

    @Test("A row with no quote is skipped rather than read as zero")
    func missingQuote() {
        // Every `below` alert in the list would fire the first time a fetch failed if an absent quote were
        // treated as a price of nothing — a dead network turned into a screenful of notifications.
        let entry = watched("VCB", alerts: [PriceAlert(direction: .below, threshold: 55_000,
                                                       currentPrice: 59_000)])
        let (fired, updated) = AlertEngine.evaluate([entry], quotes: [:])
        #expect(fired.isEmpty)
        #expect(updated == [entry])
    }

    @Test("Evaluation reports what crossed and hands back the list as it must now be stored")
    func evaluate() {
        let entries = [
            watched("VCB", alerts: [PriceAlert(direction: .above, threshold: 60_000, currentPrice: 59_000)]),
            watched("MBB", alerts: [PriceAlert(direction: .below, threshold: 20_000, currentPrice: 21_000)]),
            watched("FPT", alerts: []),
        ]
        let quotes = [
            "vietnam:VCB": quote("VCB", 60_500),
            "vietnam:MBB": quote("MBB", 21_500),
            "vietnam:FPT": quote("FPT", 90_000),
        ]

        let (fired, updated) = AlertEngine.evaluate(entries, quotes: quotes)
        #expect(fired.map(\.symbol) == ["VCB"])
        #expect(fired.first?.price == 60_500)
        // The disarm has to come back with it. Losing this write is the bug that turns "fires once" into
        // "fires every minute" without changing a line of the arming logic.
        #expect(updated[0].alerts[0].isArmed == false)
        #expect(updated[1].alerts[0].isArmed == true)
        #expect(updated[2].alerts.isEmpty)
    }

    @Test("A rearm is stored even though it announces nothing")
    func rearmIsPersisted() {
        var alert = PriceAlert(direction: .above, threshold: 60_000, currentPrice: 59_000)
        alert.isArmed = false
        let entry = watched("VCB", alerts: [alert])
        let (fired, updated) = AlertEngine.evaluate([entry], quotes: ["vietnam:VCB": quote("VCB", 59_000)])
        #expect(fired.isEmpty)
        // Silent, but it is the write that lets the alert ever speak again.
        #expect(updated[0].alerts[0].isArmed == true)
    }

    @Test("The notification says the price and the line it crossed, in the panel's own spelling")
    func message() {
        let entry = watched("VCB", alerts: [PriceAlert(direction: .above, threshold: 60_000,
                                                       currentPrice: 59_000)])
        let (fired, _) = AlertEngine.evaluate([entry], quotes: ["vietnam:VCB": quote("VCB", 60_500)])
        #expect(fired.first?.title == "VCB")
        // Grouped exactly as the row draws it: an alert quoting "60500" beside a panel reading "60,500"
        // reads as a different number at a glance.
        #expect(fired.first?.body == "60,500 — above 60,000")
    }

    @Test("A typed threshold is read back the way the panel writes it")
    func parsing() {
        #expect(PriceFormat.parse("60000") == 60_000)
        #expect(PriceFormat.parse(" 60,000 ") == 60_000)          // copied off the panel
        #expect(PriceFormat.parse("4,309.43") == 4_309.43)
        #expect(PriceFormat.parse("0.00004") == 0.00004)          // a crypto token, not a group
        // Two dots cannot both be decimal points, so this is Vietnamese grouping and unambiguous.
        #expect(PriceFormat.parse("144.000.000") == 144_000_000)
        // One dot stays a decimal point, matching what the panel means by it. Guessing the other way would
        // multiply a threshold by a thousand silently.
        #expect(PriceFormat.parse("60.000") == 60)
        #expect(PriceFormat.parse("") == nil)
        #expect(PriceFormat.parse("abc") == nil)
        #expect(PriceFormat.parse("60k") == nil)
    }

    @Test("A row stored before alerts existed still decodes, and keeps none")
    func decodesBlobWithoutAlerts() throws {
        // The regression this caught on the way in: a property default does NOT make a Codable key
        // optional, so adding `alerts` briefly made every previously stored row undecodable. Nothing was
        // deleted — WatchlistCoding carried them — but the watchlist rendered as the shipped defaults, an
        // upgrade that silently emptied the panel.
        let old = Data(#"{"symbol":"VCB","market":"vietnam","pinnedToMenuBar":true}"#.utf8)
        let entry = try JSONDecoder().decode(WatchedSymbol.self, from: old)
        #expect(entry.symbol == "VCB")
        #expect(entry.pinnedToMenuBar)
        #expect(entry.alerts.isEmpty)

        // And a round trip through this build keeps them.
        let entryWithAlert = watched("VCB", alerts: [PriceAlert(direction: .above, threshold: 60_000,
                                                                currentPrice: 59_000)])
        let round = try JSONDecoder().decode(
            WatchedSymbol.self, from: try JSONEncoder().encode(entryWithAlert))
        #expect(round == entryWithAlert)
    }

    // MARK: - Helpers

    private func watched(_ symbol: String, alerts: [PriceAlert]) -> WatchedSymbol {
        var entry = WatchedSymbol(symbol: symbol, market: .vietnam, pinnedToMenuBar: false)
        entry.alerts = alerts
        return entry
    }

    private func quote(_ symbol: String, _ price: Double) -> Quote {
        Quote(symbol: symbol, market: .vietnam, price: price, reference: nil,
              ceiling: nil, floor: nil, volume: nil, asOf: Date())
    }
}
