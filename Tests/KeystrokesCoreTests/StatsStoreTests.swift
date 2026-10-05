import Testing
import Foundation
@testable import KeystrokesCore

@Suite
final class StatsStoreTests {
    private var directory: URL!

    init() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("keystrokes-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: directory)
    }

    private func writeLegacy(_ records: [String: Any]) throws -> URL {
        let url = directory.appendingPathComponent("octomouse.plist")
        try PropertyListSerialization.data(fromPropertyList: records, format: .binary, options: 0).write(to: url)
        return url
    }

    private func record(keys: Int = 120) -> [String: Any] {
        ["initializedDate": Date(timeIntervalSince1970: 1_650_000_000),
         "elapsedSeconds": 300, "mouseDown": [12, 3], "scrollWheelDistance": [1.5, 2.0, 0.0],
         "keyCodeDown": [keys] + Array(repeating: 0, count: 127), "mouseDistance": 123.5, "keyDown": keys]
    }

    @Test
    func testMigrationPreservesFieldsAndRepeatedImportDoesNotDoubleCount() throws {
        let url = try writeLegacy(["2022-05-13": record(), "global": record(keys: 999), "preferences": ["distanceUnit": 0]])
        let legacy = try OctoMouseImport.read(url)
        #expect(legacy.count == 1)
        #expect(legacy[0].keyCodeDown.count == 128)
        #expect(legacy[0].scrollWheelDistance == [1.5, 2.0, 0.0])
        #expect(legacy[0].mouseDistance == 123.5)
        let store = try StatsStore(url: directory.appendingPathComponent("stats.sqlite"))
        #expect(try store.importHistory(legacy) == ImportResult(imported: 1, skipped: 0))
        #expect(try store.importHistory(legacy) == ImportResult(imported: 0, skipped: 1))
        #expect(try store.days() == [DayStats(day: "2022-05-13", keys: 120, clicks: 15)])
        #expect(try store.importedDays() == 1)
    }

    @Test
    func testNativeCountsPersistAndAppTotalsAgreeWithDailyTotals() throws {
        let url = directory.appendingPathComponent("stats.sqlite")
        var store: StatsStore? = try StatsStore(url: url)
        try store!.record(day: "2026-10-05", bundleID: "com.example.one", appName: "One", keys: 3, clicks: 2)
        try store!.record(day: "2026-10-05", bundleID: "com.example.one", appName: "One", keys: 4, clicks: 1)
        try store!.record(day: "2026-10-05", bundleID: "com.example.two", appName: "Two", keys: 2, clicks: 5)
        try store!.setMetadata("initialImportAttempted", value: "yes")
        store = nil
        let reopened = try StatsStore(url: url)
        #expect(try reopened.days() == [DayStats(day: "2026-10-05", keys: 9, clicks: 8)])
        let apps = try reopened.apps(day: "2026-10-05")
        #expect(apps.count == 2)
        #expect(apps.reduce(0) { $0 + $1.keys } == 9)
        #expect(apps.reduce(0) { $0 + $1.clicks } == 8)
        #expect(try reopened.metadata("initialImportAttempted") == "yes")
    }

    @Test
    func testReimportKeepsFrozenBaselineAndSkipsDatesWithNativeActivity() throws {
        let first = try OctoMouseImport.read(writeLegacy(["2026-10-04": record(keys: 100)]))
        let store = try StatsStore(url: directory.appendingPathComponent("stats.sqlite"))
        _ = try store.importHistory(first)
        try store.record(day: "2026-10-04", bundleID: "app", appName: "App", keys: 7, clicks: 0)
        try store.record(day: "2026-10-05", bundleID: "app", appName: "App", keys: 2, clicks: 0)
        let later = try OctoMouseImport.read(writeLegacy([
            "2026-10-03": record(keys: 50), "2026-10-04": record(keys: 200), "2026-10-05": record(keys: 300)]))
        #expect(try store.importHistory(later) == ImportResult(imported: 1, skipped: 2))
        #expect(try store.days().map(\.keys) == [50, 107, 2])
    }

    @Test
    func testMalformedImportFailsBeforeWritingAnything() throws {
        let url = try writeLegacy(["2022-05-13": record(), "2022-05-14": ["keyDown": 1]])
        #expect(throws: (any Error).self) { try OctoMouseImport.read(url) }
        let negative = try writeLegacy(["2022-05-13": record(keys: -1)])
        #expect(throws: (any Error).self) { try OctoMouseImport.read(negative) }
    }

    @Test
    func testCSVExportMatchesPersistedTotals() throws {
        let store = try StatsStore(url: directory.appendingPathComponent("stats.sqlite"))
        try store.record(day: "2026-10-05", bundleID: "app", appName: "App", keys: 10, clicks: 2)
        let csv = directory.appendingPathComponent("export.csv")
        try store.exportCSV(to: csv)
        #expect(try String(contentsOf: csv, encoding: .utf8) == "date,keystrokes,mouse_clicks\n2026-10-05,10,2\n")
    }

    @Test
    func testDayKeyUsesLocalCalendarAtMidnight() {
        let utc = TimeZone(secondsFromGMT: 0)!
        let madrid = TimeZone(secondsFromGMT: 7200)!
        let date = ISO8601DateFormatter().date(from: "2026-10-04T23:30:00Z")!
        #expect(DayKey.string(date, timeZone: utc) == "2026-10-04")
        #expect(DayKey.string(date, timeZone: madrid) == "2026-10-05")
    }

    // Opt-in local integration check; real user history never becomes a fixture.
    @Test
    func testInstalledOctoMouseMigration() throws {
        guard let path = ProcessInfo.processInfo.environment["KEYSTROKES_OCTOMOUSE_PLIST"] else {
            return
        }
        let days = try OctoMouseImport.read(URL(fileURLWithPath: path))
        let store = try StatsStore(url: directory.appendingPathComponent("stats.sqlite"))
        #expect(try store.importHistory(days).imported == days.count)
        #expect(try store.days().reduce(Int64(0)) { $0 + $1.keys } == days.reduce(Int64(0)) { $0 + $1.keyDown })
        #expect(try store.days().reduce(Int64(0)) { $0 + $1.clicks } == days.reduce(Int64(0)) { $0 + $1.clicks })
        #expect(try store.importHistory(days).imported == 0)
    }
}
