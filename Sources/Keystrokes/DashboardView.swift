import SwiftUI
import Charts
import KeystrokesCore

struct DashboardView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        let history = HistorySummary.make(days: model.days, range: model.historyRange)
        ScrollView {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Keystrokes").font(.title2.bold())
                    HStack(spacing: 5) {
                        Circle().fill(model.monitoring ? Color.green : Color.orange).frame(width: 6, height: 6)
                        Text(model.status).font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Text("v0").font(.caption.monospaced()).foregroundStyle(.secondary)
                    .padding(.horizontal, 9).padding(.vertical, 4).background(.quaternary, in: Capsule())
            }

            if !model.monitoring {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Allow Input Monitoring to start counting.").font(.subheadline.bold())
                    Text("Enable Keystrokes in System Settings. macOS may ask you to quit and reopen it.")
                        .font(.caption).foregroundStyle(.secondary)
                    Button("Open Input Monitoring", action: model.requestPermission).buttonStyle(.borderedProminent)
                }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.orange.opacity(0.10), in: RoundedRectangle(cornerRadius: 12))
            }

            HStack(spacing: 12) {
                counter("Keystrokes today", value: model.today?.keys ?? 0, icon: "keyboard", color: .indigo)
                counter("Clicks today", value: model.today?.clicks ?? 0, icon: "cursorarrow.click", color: .teal)
            }

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Picker("Time frame", selection: $model.historyRange) {
                        ForEach(HistoryRange.allCases) { range in Text(range.title).tag(range) }
                    }
                    .pickerStyle(.menu).labelsHidden().fixedSize()
                    .font(.headline)
                    Spacer()
                    Picker("Metric", selection: $model.metric) { Text("Keys").tag("Keys"); Text("Clicks").tag("Clicks") }
                        .pickerStyle(.segmented).labelsHidden().frame(width: 135)
                }
                Chart(history.buckets) { bucket in
                    BarMark(x: .value("Period", bucket.date, unit: model.historyRange.component),
                            y: .value(model.metric, model.metric == "Keys" ? bucket.keys : bucket.clicks))
                        .foregroundStyle(model.metric == "Keys" ? Color.indigo.gradient : Color.teal.gradient)
                        .cornerRadius(4)
                }
                .chartXAxis {
                    switch model.historyRange {
                    case .sevenDays:
                        AxisMarks(values: .stride(by: .day)) { _ in AxisValueLabel(format: .dateTime.weekday(.abbreviated)) }
                    case .thirtyDays:
                        AxisMarks(values: .stride(by: .day, count: 7)) { _ in
                            AxisValueLabel(format: .dateTime.day().month(.abbreviated), centered: false, anchor: .topTrailing)
                        }
                    case .year:
                        AxisMarks(values: .stride(by: .month, count: 2)) { _ in
                            AxisValueLabel(format: .dateTime.month(.abbreviated), centered: false, anchor: .topTrailing)
                        }
                    case .all:
                        AxisMarks(values: .automatic(desiredCount: 5)) { _ in
                            AxisValueLabel(format: .dateTime.month(.abbreviated).year(.twoDigits), centered: false, anchor: .topTrailing)
                        }
                    }
                }
                .chartYAxis { AxisMarks(position: .leading) }
                .frame(height: 130)
            }

            HStack {
                Label("\(history.keys.formatted()) keys", systemImage: "keyboard")
                Spacer()
                Text("\(history.clicks.formatted()) clicks")
            }.font(.caption).foregroundStyle(.secondary)
            Text("\(history.recordedDays.formatted()) recorded days · \(model.historyRange.granularity)")
                .font(.caption2).foregroundStyle(.tertiary).padding(.top, -12)

            Divider()
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Apps today").font(.headline)
                    Spacer()
                    Button { model.showExclusions.toggle() } label: { Image(systemName: "slider.horizontal.3") }
                        .buttonStyle(.plain).help("App exclusions")
                }
                if model.apps.isEmpty {
                    Text("App counts appear as you type and click. Imported history has no app breakdown.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                ForEach(model.apps) { app in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(app.name).font(.subheadline)
                            Text(app.bundleID).font(.caption2).foregroundStyle(.tertiary).textSelection(.enabled)
                        }
                        Spacer()
                        Text("\(app.keys.formatted()) keys · \(app.clicks.formatted()) clicks")
                            .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    }
                }
                if model.showExclusions {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Exclude apps by bundle ID, separated by commas.").font(.caption)
                        TextField("com.apple.Terminal, com.example.app", text: $model.excludedApps)
                            .textFieldStyle(.roundedBorder)
                        Text("Applies to future counts. Keystrokes excludes itself automatically.")
                            .font(.caption2).foregroundStyle(.secondary)
                    }.padding(10).background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
                }
            }

            if let notice = model.notice {
                Text(notice).font(.caption).foregroundStyle(.secondary)
            } else if model.importedDays > 0 {
                Text("\(model.importedDays.formatted()) OctoMouse days preserved.").font(.caption).foregroundStyle(.secondary)
            }
            if let error = model.error {
                HStack(alignment: .top) {
                    Text(error).font(.caption).foregroundStyle(.red).textSelection(.enabled)
                    Spacer()
                    Button { model.error = nil } label: { Image(systemName: "xmark") }.buttonStyle(.plain)
                }
            }

            Divider()
            footer
        }
        .padding(22)
        }
        .frame(width: 460)
        .frame(height: 650)
        .alert("Start Keystrokes at login?", isPresented: $model.showLaunchAtLoginPrompt) {
            Button("Enable") { model.finishLaunchAtLoginPrompt(enabled: true) }
            Button("Not now", role: .cancel) { model.finishLaunchAtLoginPrompt(enabled: false) }
        } message: {
            Text("Keep counting automatically when you sign in to your Mac. You can change this later with Launch at login.")
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 16) {
                Menu("Data…") {
                    Button("Import OctoMouse…", action: model.importOctoMouse)
                    Button("Export daily totals…", action: model.exportCSV)
                    Button("Show database in Finder", action: model.revealData)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()

                Spacer()
                Button("Quit") { NSApplication.shared.terminate(nil) }
                    .buttonStyle(.plain)
                    .padding(.vertical, 4)
                    .help("Quit Keystrokes")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .controlSize(.small)

            Toggle("Launch at login", isOn: Binding(
                get: { model.launchAtLoginEnabled },
                set: { model.setLaunchAtLogin($0) }
            )).toggleStyle(.checkbox).font(.caption)

            if model.launchAtLoginNeedsApproval {
                Text("Approve Keystrokes in Login Items to enable automatic launch.")
                    .font(.caption).foregroundStyle(.secondary)
                Button("Open Login Items", action: model.openLoginSettings).controlSize(.small)
            }
            Text("Stored locally on your Mac")
                .font(.caption2).foregroundStyle(.secondary)
        }
    }

    private func counter(_ label: String, value: Int64, icon: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: icon).font(.title3).foregroundStyle(color)
            Text(value.formatted()).font(.system(size: 30, weight: .semibold, design: .rounded)).monospacedDigit()
            Text(label).font(.caption).foregroundStyle(.secondary)
        }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .background(color.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
    }
}
