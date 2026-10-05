import SwiftUI
import AppKit
import Combine
import Darwin
import Carbon
import KeystrokesCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var dashboardWindow: NSWindow?
    private var statusItem: NSStatusItem?
    private let popover = NSPopover()
    private var subscription: AnyCancellable?
    private lazy var activityIcon: NSImage? = {
        let image = NSImage(named: "StatusIcon") ?? NSImage(systemSymbolName: "keyboard", accessibilityDescription: "Keystrokes")
        image?.size = NSSize(width: 18, height: 18)
        image?.isTemplate = true
        image?.accessibilityDescription = "Keystrokes"
        return image
    }()

    func applicationDidFinishLaunching(_ notification: Notification) {
        let model = AppModel.shared
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem = item
        if let button = item.button {
            button.image = activityIcon
            button.imagePosition = .imageLeading
            button.target = self
            button.action = #selector(togglePopover)
            button.toolTip = "Keystrokes"
        }
        popover.behavior = .transient
        popover.contentSize = NSSize(width: 460, height: 650)
        popover.contentViewController = NSHostingController(rootView: DashboardView(model: model))
        subscription = model.$days.sink { [weak self] days in
            let day = DayKey.string()
            let keys = days.first { $0.day == day }?.keys ?? 0
            self?.statusItem?.button?.title = " " + keys.formatted(.number.notation(.compactName))
        }
        let launchedAtLogin = NSAppleEventManager.shared().currentAppleEvent?
            .paramDescriptor(forKeyword: keyAEPropData)?.enumCodeValue == keyAELaunchedAsLogInItem
        if !launchedAtLogin || model.showLaunchAtLoginPrompt { showDashboard() }
    }

    @objc private func togglePopover() {
        guard let button = statusItem?.button else { return }
        if popover.isShown { popover.performClose(nil) }
        else { popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY) }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showDashboard()
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func windowWillClose(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }

    private func showDashboard() {
        if dashboardWindow == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 460, height: 650),
                                  styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
            window.title = "Keystrokes"
            window.delegate = self
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: DashboardView(model: AppModel.shared))
            window.center()
            dashboardWindow = window
        }
        NSApp.setActivationPolicy(.regular)
        dashboardWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        AppModel.shared.stop()
        return .terminateNow
    }
}

@main
enum KeystrokesLauncher {
    @MainActor
    static func main() {
        if CommandLine.arguments.contains("--prepare-history") {
            do {
                let store = try StatsStore(url: StatsStore.defaultURL)
                // Read this one known file through the terminal's existing access.
                if try store.importedDays() == 0, FileManager.default.fileExists(atPath: OctoMouseImport.defaultURL.path) {
                    let result = try store.importHistory(OctoMouseImport.read(OctoMouseImport.defaultURL))
                    try store.setMetadata("initialImportAttempted", value: "yes")
                    print("OctoMouse: imported \(result.imported) days; kept \(result.skipped) existing dates.")
                }
            } catch {
                print("OctoMouse import: \(error.localizedDescription) Use Data → Import OctoMouse in the app to retry.")
            }
            return
        }
        // Two copies of the app must never record the same input into one database.
        let folder = StatsStore.defaultURL.deletingLastPathComponent()
        do { try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true) }
        catch { fputs("Could not create the data folder: \(error.localizedDescription)\n", stderr); return }
        let lock = open(folder.appendingPathComponent("instance.lock").path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard lock >= 0 else { fputs("Could not open the instance lock.\n", stderr); return }
        defer { close(lock) }
        guard flock(lock, LOCK_EX | LOCK_NB) == 0 else {
            NSRunningApplication.runningApplications(withBundleIdentifier: "io.mikatre.keystrokes")
                .first { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }?
                .activate(options: [])
            return
        }
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
        withExtendedLifetime(delegate) {}
    }
}
