import Foundation

public enum HistoryRange: String, CaseIterable, Identifiable, Sendable {
    case sevenDays, thirtyDays, year, all

    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .sevenDays: "Last 7 days"
        case .thirtyDays: "Last 30 days"
        case .year: "Last 12 months"
        case .all: "All history"
        }
    }
    public var component: Calendar.Component {
        switch self {
        case .sevenDays, .thirtyDays: .day
        case .year: .weekOfYear
        case .all: .month
        }
    }
    public var granularity: String {
        switch self {
        case .sevenDays, .thirtyDays: "Daily totals"
        case .year: "Weekly totals"
        case .all: "Monthly totals"
        }
    }
}

public struct HistoryBucket: Identifiable, Sendable {
    public var id: Date { date }
    public let date: Date
    public let keys: Int64
    public let clicks: Int64
}

public struct HistorySummary: Sendable {
    public let start: Date
    public let end: Date
    public let buckets: [HistoryBucket]
    public let keys: Int64
    public let clicks: Int64
    public let recordedDays: Int

    public static func make(days: [DayStats], range: HistoryRange, now: Date = .now,
                            calendar: Calendar = .current) -> HistorySummary {
        let today = calendar.startOfDay(for: now)
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today)!
        let dated = days.compactMap { day -> (date: Date, stats: DayStats)? in
            let parts = day.day.split(separator: "-").compactMap { Int($0) }
            guard parts.count == 3,
                  let date = calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2])),
                  DayKey.string(date, timeZone: calendar.timeZone) == day.day,
                  date < tomorrow else { return nil }
            return (date, day)
        }
        let start: Date
        switch range {
        case .sevenDays: start = calendar.date(byAdding: .day, value: -6, to: today)!
        case .thirtyDays: start = calendar.date(byAdding: .day, value: -29, to: today)!
        case .year: start = calendar.date(byAdding: .year, value: -1, to: tomorrow)!
        case .all: start = dated.map(\.date).min() ?? today
        }
        var totals: [Date: (keys: Int64, clicks: Int64)] = [:]
        var recordedDays = 0
        for day in dated where day.date >= start {
            let bucket = calendar.dateInterval(of: range.component, for: day.date)!.start
            let previous = totals[bucket] ?? (0, 0)
            totals[bucket] = (previous.keys + day.stats.keys, previous.clicks + day.stats.clicks)
            recordedDays += 1
        }
        var buckets: [HistoryBucket] = []
        var date = calendar.dateInterval(of: range.component, for: start)!.start
        while date < tomorrow {
            let counts = totals[date] ?? (0, 0)
            buckets.append(HistoryBucket(date: date, keys: counts.keys, clicks: counts.clicks))
            date = calendar.date(byAdding: range.component, value: 1, to: date)!
        }
        return HistorySummary(start: start, end: tomorrow, buckets: buckets,
                              keys: buckets.reduce(0) { $0 + $1.keys },
                              clicks: buckets.reduce(0) { $0 + $1.clicks }, recordedDays: recordedDays)
    }
}
