import AppKit
import SwiftUI
import KeystrokesCore
import UniformTypeIdentifiers
import ServiceManagement

@MainActor
final class AppModel: ObservableObject {
    static let shared = AppModel()
    @Published var days: [DayStats] = []
    @Published var apps: [AppStats] = []
    @Published var importedDays = 0
    @Published var monitoring = false
    @Published var error: String?
    @Published var notice: String?
    @Published var showExclusions = false
    @Published var metric = "Keys"
    @Published var historyRange = HistoryRange.sevenDays
    @Published var showLaunchAtLoginPrompt = false
    @Published private(set) var loginItemStatus = SMAppService.mainApp.status
    var launchAtLoginEnabled: Bool { loginItemStatus == .enabled }
    var launchAtLoginNeedsApproval: Bool { loginItemStatus == .requiresApproval }
    @Published var excludedApps: String {
        didSet { UserDefaults.standard.set(excludedApps, forKey: "excludedApps") }
    }
    let databaseURL: URL
    private var store: StatsStore?
    private let monitor = InputMonitor()
    private var timer: Timer?
    private var pending: [Bucket: Counts] = [:]
    private var lastRetry = Date.distantPast

    private struct Bucket: Hashable {
        let day: String
        let bundleID: String
        let name: String
    }
    private struct Counts {
        var keys: Int64 = 0
        var clicks: Int64 = 0
    }

    var today: DayStats? {
        let day = DayKey.string()
        return days.first { $0.day == day }
    }
    var status: String {
        if store == nil { return "Storage unavailable" }
        if !monitoring { return "Input Monitoring permission needed" }
        return "Counting on this Mac"
    }

    private init() {
        excludedApps = UserDefaults.standard.string(forKey: "excludedApps") ?? ""
        databaseURL = StatsStore.defaultURL
        do {
            let store = try StatsStore(url: databaseURL)
            self.store = store
            // Read the baseline before we begin collecting. Original data is untouched.
            if try store.metadata("initialImportAttempted") == nil {
                if FileManager.default.fileExists(atPath: OctoMouseImport.defaultURL.path) {
                    let result = try store.importHistory(OctoMouseImport.read(OctoMouseImport.defaultURL))
                    notice = "Imported \(result.imported.formatted()) days from OctoMouse."
                    try store.setMetadata("initialImportAttempted", value: "yes")
                }
            }
            try refresh()
        } catch { self.error = error.localizedDescription }
        monitor.onInput = { [weak self] key in self?.receive(key: key) }
        if store != nil { monitoring = monitor.start() }
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(timer!, forMode: .common)
        showLaunchAtLoginPrompt = !UserDefaults.standard.bool(forKey: "launchAtLoginAsked") && !launchAtLoginEnabled
    }

    private func receive(key: Bool) {
        guard store != nil else { return }
        guard let app = NSWorkspace.shared.frontmostApplication else { return }
        let bundle = app.bundleIdentifier ?? "pid:\(app.processIdentifier)"
        guard bundle != Bundle.main.bundleIdentifier else { return }
        let exclusions = Set(excludedApps.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty })
        guard !exclusions.contains(bundle) else { return }
        let bucket = Bucket(day: DayKey.string(), bundleID: bundle, name: app.localizedName ?? bundle)
        var counts = pending[bucket] ?? Counts()
        if key { counts.keys += 1 } else { counts.clicks += 1 }
        pending[bucket] = counts
    }

    private func tick() {
        let loginStatus = SMAppService.mainApp.status
        if loginItemStatus != loginStatus { loginItemStatus = loginStatus }
        flush()
        if store != nil, !monitor.isRunning, Date.now.timeIntervalSince(lastRetry) > 3 {
            lastRetry = .now
            let running = monitor.start()
            if monitoring != running { monitoring = running }
        } else if monitoring != monitor.isRunning { monitoring = monitor.isRunning }
        do { try refresh() } catch { self.error = error.localizedDescription }
    }

    func flush() {
        guard let store else { return }
        for (bucket, counts) in Array(pending) {
            do {
                try store.record(day: bucket.day, bundleID: bucket.bundleID, appName: bucket.name, keys: counts.keys, clicks: counts.clicks)
                pending.removeValue(forKey: bucket)
            } catch { self.error = "Could not save counts: \(error.localizedDescription)"; break }
        }
    }

    private func refresh() throws {
        guard let store else { return }
        let newDays = try store.days()
        let newApps = try store.apps(day: DayKey.string())
        let newImportedDays = try store.importedDays()
        if days != newDays { days = newDays }
        if apps != newApps { apps = newApps }
        if importedDays != newImportedDays { importedDays = newImportedDays }
    }

    func requestPermission() {
        _ = CGRequestListenEventAccess()
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent") {
            NSWorkspace.shared.open(url)
        }
        monitoring = monitor.start()
    }

    func importOctoMouse() {
        flush()
        guard let store else { return }
        let panel = NSOpenPanel()
        panel.title = "Import OctoMouse history"
        panel.message = "Choose OctoMouse’s preferences .plist file. Existing dates are kept to avoid double-counting."
        panel.allowedContentTypes = [.propertyList]
        panel.directoryURL = OctoMouseImport.defaultURL.deletingLastPathComponent()
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let result = try store.importHistory(OctoMouseImport.read(url))
            notice = "Imported \(result.imported.formatted()) days; kept \(result.skipped.formatted()) existing dates."
            try refresh()
        } catch { self.error = error.localizedDescription }
    }

    func exportCSV() {
        flush()
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "Keystrokes-\(DayKey.string()).csv"
        panel.allowedContentTypes = [.commaSeparatedText]
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            guard let store else { throw DataError.message("Storage is unavailable.") }
            try store.exportCSV(to: url)
            notice = "Daily totals exported."
        } catch { self.error = error.localizedDescription }
    }

    func revealData() { NSWorkspace.shared.activateFileViewerSelecting([databaseURL]) }

    func finishLaunchAtLoginPrompt(enabled: Bool) {
        UserDefaults.standard.set(true, forKey: "launchAtLoginAsked")
        showLaunchAtLoginPrompt = false
        if enabled { setLaunchAtLogin(true) }
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                if SMAppService.mainApp.status != .enabled && SMAppService.mainApp.status != .requiresApproval {
                    try SMAppService.mainApp.register()
                }
            } else {
                try SMAppService.mainApp.unregister()
            }
            loginItemStatus = SMAppService.mainApp.status
            if launchAtLoginNeedsApproval { openLoginSettings() }
        } catch {
            loginItemStatus = SMAppService.mainApp.status
            self.error = "Could not change launch at login: \(error.localizedDescription)"
        }
    }

    func openLoginSettings() { SMAppService.openSystemSettingsLoginItems() }

    func stop() {
        monitor.stop()
        timer?.invalidate()
        flush()
    }
}
