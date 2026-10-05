import Foundation

public struct DayStats: Identifiable, Equatable, Sendable {
    public var id: String { day }
    public let day: String
    public let keys: Int64
    public let clicks: Int64
}

public struct AppStats: Identifiable, Equatable, Sendable {
    public var id: String { bundleID }
    public let bundleID: String
    public let name: String
    public let keys: Int64
    public let clicks: Int64
}

public struct LegacyDay: Codable, Sendable {
    public let day: String
    public let initializedDate: Date
    public let elapsedSeconds: Int64
    public let mouseDown: [Int64]
    public let scrollWheelDistance: [Double]
    public let keyCodeDown: [Int64]
    public let mouseDistance: Double
    public let keyDown: Int64

    public var clicks: Int64 { mouseDown.reduce(0, +) }
}

public struct ImportResult: Equatable, Sendable {
    public let imported: Int
    public let skipped: Int
}

public enum DayKey {
    public static func string(_ date: Date = .now, timeZone: TimeZone = .current) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year!, parts.month!, parts.day!)
    }
}

public enum OctoMouseImport {
    public static var defaultURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Containers/com.takohi.octomouse/Data/Library/Preferences/com.takohi.octomouse.plist")
    }

    public static func read(_ url: URL) throws -> [LegacyDay] {
        let data = try Data(contentsOf: url)
        guard let root = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
            throw DataError.message("This file is not an OctoMouse preferences file.")
        }
        let days = try root.keys.filter { $0.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil }
            .sorted().map { day in
                guard let record = root[day] as? [String: Any],
                      let initialized = record["initializedDate"] as? Date,
                      let elapsed = record["elapsedSeconds"] as? NSNumber,
                      let keys = record["keyDown"] as? NSNumber,
                      let distance = record["mouseDistance"] as? NSNumber,
                      let buttons = record["mouseDown"] as? [NSNumber], buttons.count == 2,
                      let scroll = record["scrollWheelDistance"] as? [NSNumber], scroll.count == 3,
                      let histogram = record["keyCodeDown"] as? [NSNumber], histogram.count == 128 else {
                    throw DataError.message("Invalid OctoMouse record for \(day). Nothing was imported.")
                }
                let counts = [elapsed, keys] + buttons + histogram
                guard counts.allSatisfy({ $0.doubleValue.isFinite && $0.doubleValue >= 0 && $0.doubleValue < Double(Int64.max) && $0.doubleValue.rounded() == $0.doubleValue }),
                      ([distance] + scroll).allSatisfy({ $0.doubleValue.isFinite && $0.doubleValue >= 0 }),
                      buttons.reduce(0.0, { $0 + $1.doubleValue }) < Double(Int64.max) else {
                    throw DataError.message("Invalid counters for \(day). Nothing was imported.")
                }
                return LegacyDay(day: day, initializedDate: initialized, elapsedSeconds: elapsed.int64Value,
                                 mouseDown: buttons.map(\.int64Value), scrollWheelDistance: scroll.map(\.doubleValue),
                                 keyCodeDown: histogram.map(\.int64Value), mouseDistance: distance.doubleValue,
                                 keyDown: keys.int64Value)
            }
        guard !days.isEmpty else { throw DataError.message("No daily OctoMouse records found in this file.") }
        return days
    }
}

public enum DataError: LocalizedError {
    case message(String)
    public var errorDescription: String? {
        switch self { case .message(let message): return message }
    }
}
