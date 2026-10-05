import Foundation
import Testing
@testable import KeystrokesCore

struct HistoryTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = TimeZone(identifier: "Europe/Madrid")!
        return calendar
    }

    private func date(_ value: String) -> Date {
        ISO8601DateFormatter().date(from: value + "T12:00:00Z")!
    }

    @Test
    func dailyRangesIncludeTodayAndHandleDaylightSaving() {
        let days = [DayStats(day: "2024-03-26", keys: 100, clicks: 100),
                    DayStats(day: "2024-03-27", keys: 2, clicks: 3),
                    DayStats(day: "2024-03-31", keys: 5, clicks: 7),
                    DayStats(day: "2024-04-02", keys: 11, clicks: 13),
                    DayStats(day: "2024-04-03", keys: 1000, clicks: 1000)]
        let week = HistorySummary.make(days: days, range: .sevenDays, now: date("2024-04-02"), calendar: calendar)
        #expect(week.buckets.count == 7)
        #expect(week.keys == 18)
        #expect(week.clicks == 23)
        #expect(week.recordedDays == 3)
        #expect(week.buckets.map { DayKey.string($0.date, timeZone: calendar.timeZone) } ==
                ["2024-03-27", "2024-03-28", "2024-03-29", "2024-03-30", "2024-03-31", "2024-04-01", "2024-04-02"])
        let month = HistorySummary.make(days: days, range: .thirtyDays, now: date("2024-04-02"), calendar: calendar)
        #expect(month.buckets.count == 30)
        #expect(month.keys == 118)
        #expect(month.clicks == 123)
    }

    @Test
    func yearUsesCalendarWeeksAcrossNewYearAndExcludesOldDays() {
        let days = [DayStats(day: "2025-01-02", keys: 1000, clicks: 1000),
                    DayStats(day: "2025-12-28", keys: 2, clicks: 3),
                    DayStats(day: "2025-12-29", keys: 5, clicks: 7),
                    DayStats(day: "2026-01-01", keys: 11, clicks: 13)]
        let year = HistorySummary.make(days: days, range: .year, now: date("2026-01-02"), calendar: calendar)
        #expect(DayKey.string(year.start, timeZone: calendar.timeZone) == "2025-01-03")
        #expect(year.keys == 18)
        #expect(year.clicks == 23)
        let newYearWeek = year.buckets.first { DayKey.string($0.date, timeZone: calendar.timeZone) == "2025-12-29" }
        #expect(newYearWeek?.keys == 16)
        #expect(newYearWeek?.clicks == 20)
        #expect(year.recordedDays == 3)
    }

    @Test
    func allHistoryAggregatesUnsortedDaysAndFillsMissingMonths() {
        let days = [DayStats(day: "2026-10-05", keys: 11, clicks: 13),
                    DayStats(day: "2022-05-13", keys: 2, clicks: 3),
                    DayStats(day: "2022-05-31", keys: 5, clicks: 7),
                    DayStats(day: "2022-07-01", keys: 17, clicks: 19)]
        let all = HistorySummary.make(days: days, range: .all, now: date("2026-10-05"), calendar: calendar)
        #expect(all.buckets.count == 54)
        #expect(all.buckets[0].keys == 7)
        #expect(all.buckets[1].keys == 0)
        #expect(all.buckets[2].keys == 17)
        #expect(all.buckets.last?.keys == 11)
        #expect(all.keys == 35)
        #expect(all.clicks == 42)
        #expect(all.recordedDays == 4)
        #expect(DayKey.string(all.start, timeZone: calendar.timeZone) == "2022-05-13")
    }

    @Test
    func emptyHistoryAndLeapYearHaveValidBounds() {
        let empty = HistorySummary.make(days: [], range: .all, now: date("2026-10-05"), calendar: calendar)
        #expect(empty.buckets.count == 1)
        #expect(empty.keys == 0)
        #expect(empty.recordedDays == 0)
        let year = HistorySummary.make(days: [DayStats(day: "2024-02-29", keys: 2, clicks: 3)],
                                       range: .year, now: date("2025-02-28"), calendar: calendar)
        #expect(DayKey.string(year.start, timeZone: calendar.timeZone) == "2024-03-01")
        #expect(year.keys == 0)
    }
}
