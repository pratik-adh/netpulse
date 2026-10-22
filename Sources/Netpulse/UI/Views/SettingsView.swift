import SwiftUI
import AppKit

struct SettingsView: View {
    @ObservedObject var model: AppModel
    @State private var selection = 0

    var body: some View {
        TabView(selection: $selection) {
            UsageTab(model: model)
                .tabItem { Label("Usage", systemImage: "arrow.up.arrow.down") }
                .tag(0)
            GeneralTab(model: model)
                .tabItem { Label("General", systemImage: "gearshape.fill") }
                .tag(1)
            SupportTab()
                .tabItem { Label("Support", systemImage: "heart.fill") }
                .tag(2)
        }
        .frame(width: 560, height: 520)
        // macOS draws the tab bar and the bezel *outside* the TabView's layout
        // bounds, so the TabView needs a margin to sit in. Flush against the
        // window edge the bar overhangs the top and gets clipped.
        .padding(12)
    }
}

// MARK: - Shared helpers

extension View {
    /// Builds a binding into the model's settings through a writable key path,
    /// so every edit goes through `AppModel.settings` and gets persisted.
    func settingsBinding<T>(_ model: AppModel,
                            _ keyPath: WritableKeyPath<Settings, T>) -> Binding<T> {
        Binding(
            get: { model.settings[keyPath: keyPath] },
            set: { newValue in
                var copy = model.settings
                copy[keyPath: keyPath] = newValue
                model.settings = copy
            }
        )
    }
}

/// One period's totals - two rows (↓ / ↑) or one combined figure, per the
/// Display setting, so every section below reads the same way.
private struct TotalsRows: View {
    var received: Int
    var sent: Int
    var separately: Bool
    var combinedLabel: String

    var body: some View {
        if separately {
            HStack {
                Text("Downloaded")
                Spacer()
                Text(Format.bytes(received)).foregroundStyle(.secondary)
            }
            HStack {
                Text("Uploaded")
                Spacer()
                Text(Format.bytes(sent)).foregroundStyle(.secondary)
            }
        } else {
            HStack {
                Text(combinedLabel)
                Spacer()
                Text(Format.bytes(received + sent)).foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Usage

private struct UsageTab: View {
    @ObservedObject var model: AppModel
    @State private var confirmResetNetworkUsage = false

    private func limitBinding() -> Binding<Int> {
        Binding(
            get: { model.settings.dailyDataLimitMB },
            set: { newValue in
                var copy = model.settings
                copy.dailyDataLimitMB = newValue
                model.settings = copy
                if newValue > 0 {
                    NotificationManager.shared.requestAuthorizationIfNeeded()
                }
            }
        )
    }

    private func limitLabel(_ mb: Int) -> String {
        mb == 0 ? "No budget" : Format.bytes(mb * 1_000_000)
    }

    var body: some View {
        let separately = model.settings.showUploadDownloadSeparately
        Form {
            // MARK: Controls - what to track, and how to show it

            Section("Tracking") {
                if model.settings.networkTrackingEnabled {
                    Text("Tracking is on. Right-click the menu bar icon to pause it.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    HStack {
                        Text("Tracking is paused.")
                            .font(.caption)
                            .foregroundStyle(.orange)
                        Spacer()
                        Button("Resume") { settingsBinding(model, \.networkTrackingEnabled).wrappedValue = true }
                    }
                }
                Toggle("Track network usage", isOn: settingsBinding(model, \.networkTrackingEnabled))
                Text("Reads the same interface counters Activity Monitor's Network tab does. Everything stays on this Mac.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Menu bar") {
                Toggle("Show usage next to the icon",
                       isOn: settingsBinding(model, \.showUsageInMenuBar))
                if model.settings.showUsageInMenuBar {
                    Picker("Show", selection: settingsBinding(model, \.menuBarUsagePeriod)) {
                        ForEach(NetworkMenuBarPeriod.allCases) { period in
                            Text(period.title).tag(period)
                        }
                    }
                    let total = model.menuBarUsageTotal
                    let preview = separately
                        ? "↓\(Format.bytes(total.received)) ↑\(Format.bytes(total.sent))"
                        : Format.bytes(total.received + total.sent)
                    Text("\(preview) - right now. Live up/down speed is one click away, in the popover.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                } else {
                    Text("Off leaves just the icon - click it for today's usage and live speed.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Display") {
                Toggle("Show upload and download separately",
                       isOn: settingsBinding(model, \.showUploadDownloadSeparately))
                Text("Off combines both directions into one total, in the menu bar and in the figures below.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Daily data budget") {
                Picker("Notify me after", selection: limitBinding()) {
                    ForEach(Settings.dataLimitChoices, id: \.self) { mb in
                        Text(limitLabel(mb)).tag(mb)
                    }
                }
                .disabled(!model.settings.networkTrackingEnabled)
                Text("This is a nudge, not a block - Netpulse can't actually limit your internet without a much deeper (and riskier) system integration. Crossing the budget sends one notification for the day.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // MARK: Usage - day, week, month, by network, then the grand total

            Section("Today") {
                TotalsRows(received: model.todayStat.bytesReceived, sent: model.todayStat.bytesSent,
                           separately: separately, combinedLabel: "Total")
            }

            Section("This week") {
                let week = model.networkTotal(lastDays: 7)
                TotalsRows(received: week.received, sent: week.sent,
                           separately: separately, combinedLabel: "Last 7 days")
            }

            Section("This month") {
                let month = model.networkTotal(lastDays: 30)
                TotalsRows(received: month.received, sent: month.sent,
                           separately: separately, combinedLabel: "Last 30 days")
            }

            Section("By Wi-Fi network") {
                Toggle("Break down usage by Wi-Fi network",
                       isOn: settingsBinding(model, \.perNetworkUsageEnabled))
                    .disabled(!model.settings.networkTrackingEnabled)
                if model.settings.perNetworkUsageEnabled {
                    if model.perNetworkLocationDenied {
                        Text("Location access is off, so Wi-Fi names can't be read. Enable it in System Settings ▸ Privacy & Security ▸ Location Services, then turn this back on.")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    } else if model.perNetworkUsageTotals.isEmpty {
                        Text("No network history yet - check back after using the connection for a bit.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        // Already sorted by usage, largest first.
                        ForEach(model.perNetworkUsageTotals, id: \.name) { entry in
                            let isCurrent = entry.name == model.currentNetworkLabel
                            HStack(spacing: 6) {
                                Image(systemName: entry.name == "Other network" ? "cable.connector" : "wifi")
                                    .padding(.horizontal, entry.name == "Other network" ? 4 : 0)
                                    .font(.caption2)
                                    .foregroundStyle(isCurrent ? Color.green : Color.secondary)
                                Text(entry.name)
                                    .fontWeight(isCurrent ? .semibold : .regular)
                                if isCurrent {
                                    Text("now")
                                        .font(.system(size: 9, weight: .bold))
                                        .padding(.horizontal, 4)
                                        .padding(.vertical, 1)
                                        .background(Capsule().fill(Color.green.opacity(0.18)))
                                        .foregroundStyle(Color.green)
                                }
                                Spacer()
                                Text(Format.bytes(entry.received + entry.sent)).foregroundStyle(.secondary)
                            }
                        }
                    }
                    Text("Reading the current Wi-Fi name needs Location Services - a macOS restriction on SSID access, not something this app can bypass. Wired connections and unreadable networks are grouped as \"Other network.\" Nothing is ever sent anywhere; the name only labels your own local history.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Section("All-time total") {
                let total = model.allTimeNetworkTotal
                TotalsRows(received: total.received, sent: total.sent,
                           separately: separately, combinedLabel: "Total")
                Text("Across every day still in history (up to 120 days).")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Section("Reset") {
                Button("Reset usage history…", role: .destructive) {
                    confirmResetNetworkUsage = true
                }
                .confirmationDialog("Reset all tracked network usage?",
                                    isPresented: $confirmResetNetworkUsage) {
                    Button("Reset", role: .destructive) { model.resetNetworkUsage() }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("Clears today's, this week's, this month's, all-time, and per-network usage totals.")
                }
                Text("History lives in ~/Library/Application Support/Netpulse/stats.json and never leaves your Mac. Tracking itself keeps running right after a reset.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - General

private struct GeneralTab: View {
    @ObservedObject var model: AppModel
    @State private var confirmRestoreDefaults = false

    var body: some View {
        Form {
            Section("Startup") {
                Toggle("Open Netpulse at login", isOn: settingsBinding(model, \.launchAtLogin))
                if let problem = model.launchAtLoginProblem {
                    Text(problem)
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }

            Section("Reset") {
                Button("Restore all defaults", role: .destructive) {
                    confirmRestoreDefaults = true
                }
                .confirmationDialog("Restore all settings to their defaults?",
                                    isPresented: $confirmRestoreDefaults) {
                    Button("Restore Defaults", role: .destructive) { model.restoreDefaultSettings() }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("Every preference in this window goes back to its default.")
                }
                Text("Your usage history isn't touched - reset that separately, at the bottom of the Usage tab.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("About") {
                HStack(spacing: 10) {
                    Image(systemName: "waveform.path.ecg")
                        .font(.system(size: 18))
                        .foregroundStyle(Color.blue)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Netpulse 1.0").font(.system(size: 12, weight: .semibold))
                        Text("Network usage and speed, in the menu bar.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                Text("The only network request Netpulse ever makes is the speed test, and only when you tap Test Speed.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Support

private struct SupportTab: View {
    private static let coffeeURL = URL(string: "https://www.buymeacoffee.com/downtime.app")!
    private static let githubURL = URL(string: "https://github.com/pratik-adh/netpulse")!

    var body: some View {
        Form {
            Section {
                HStack(spacing: 12) {
                    Image(systemName: "waveform.path.ecg")
                        .font(.system(size: 22))
                        .foregroundStyle(Color.blue)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Enjoying Netpulse?").font(.system(size: 13, weight: .semibold))
                        Text("It's free, and stays that way. If it's saved you from a surprise data bill, a coffee helps keep it going.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Button {
                    NSWorkspace.shared.open(Self.coffeeURL)
                } label: {
                    Label("Buy me a coffee", systemImage: "cup.and.saucer.fill")
                        .frame(maxWidth: .infinity)
                }
                .controlSize(.large)
            }

            Section("What a coffee actually goes toward") {
                supportRow(symbol: "lock.shield.fill",
                           text: "No ads, no telemetry, no accounts - anywhere in this app. That's a deliberate, ongoing cost, not a one-time decision.")
                supportRow(symbol: "hammer.fill",
                           text: "Every feature here - usage tracking, the per-Wi-Fi breakdown, the speed test - is built and maintained by a person.")
                supportRow(symbol: "arrow.triangle.2.circlepath",
                           text: "Keeping up with new macOS releases, fixing bugs, and shipping the things people actually ask for.")
                supportRow(symbol: "checkmark.seal.fill",
                           text: "It doesn't unlock anything. Netpulse is fully-featured whether or not you ever buy a coffee - this is just how you say thanks.")
            }

            Section("Feedback") {
                Text("Found a bug, or have an idea? Let me know - every note gets read.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                HStack(spacing: 8) {
                    Image(systemName: "chevron.left.forwardslash.chevron.right")
                        .foregroundStyle(.secondary)
                    Text("Netpulse is open source and MIT-licensed - issues and pull requests are welcome.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("View on GitHub") {
                        NSWorkspace.shared.open(Self.githubURL)
                    }
                    .font(.caption)
                }
            }
        }
        .formStyle(.grouped)
    }

    private func supportRow(symbol: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 12))
                .foregroundStyle(Color.blue)
                .frame(width: 16)
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
