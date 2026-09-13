import SwiftUI
import AppKit

/// The network icon's popover — deliberately mirrors `PopoverView`'s shape
/// (header, hero, list, stats, footer) so the two features read as siblings,
/// even though what's inside each section is different.
struct NetworkPopoverView: View {
    @ObservedObject var model: AppModel

    private var isPaused: Bool { !model.settings.networkTrackingEnabled }

    var body: some View {
        VStack(spacing: 12) {
            header
            if isPaused {
                pausedNotice
            } else {
                hero
                Divider().opacity(0.5)
                speedTestSection
                Divider().opacity(0.5)
                if model.settings.perNetworkUsageEnabled {
                    wifiList
                } else {
                    enablePerNetworkHint
                }
            }
            footer
        }
        .padding(14)
        .frame(width: 300)
        .background(Tokens.popoverBackground)
    }

    /// While tracking is paused there's no live speed, no fresh usage, and
    /// nothing new for the Wi-Fi list to show — so the panel collapses to a
    /// single notice rather than a wall of stale, dimmed sections.
    private var pausedNotice: some View {
        VStack(spacing: 10) {
            Image(systemName: "pause.circle")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(.secondary)
            Text("Network tracking is paused")
                .font(.system(size: 13, weight: .semibold))
            Text("Resume to see live speed, usage, and run a speed test.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button {
                resume()
            } label: {
                Label("Resume Network Mode", systemImage: "play.circle.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.blue)
        }
        .padding(.vertical, 16)
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "network")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.blue)
            Text("Network")
                .font(.system(size: 14, weight: .semibold))
            Spacer()

            Button {
                isPaused ? resume() : pause()
            } label: {
                Image(systemName: isPaused ? "play.circle.fill" : "pause.circle")
            }
            .buttonStyle(.borderless)
            .help(isPaused ? "Resume Network Mode" : "Quit Network Mode")

            Button {
                openSettings()
            } label: {
                Image(systemName: "gearshape.fill")
            }
            .buttonStyle(.borderless)
            .help("Settings")
        }
    }

    // MARK: Hero — live speed, ring-styled like the break countdown

    private var hero: some View {
        HStack(spacing: 18) {
            speedRing(direction: "Down", symbol: "arrow.down", bps: model.downloadSpeedBps,
                      usage: model.todayStat.bytesReceived, tint: .blue)
            speedRing(direction: "Up", symbol: "arrow.up", bps: model.uploadSpeedBps,
                      usage: model.todayStat.bytesSent, tint: .green)
        }
        .opacity(isPaused ? 0.4 : 1)
    }

    /// An illustrative gauge, not a literal goal like the break countdown's
    /// ring — there's no natural "full" for network speed, so a soft cap
    /// keeps ordinary browsing mid-ring and only heavy transfers fill it.
    /// The ring itself stays a live speed reading; today's actual usage total
    /// sits underneath, so "how fast right now" and "how much today" are both
    /// visible without digging into Settings.
    private func speedRing(direction: String, symbol: String, bps: Double, usage: Int, tint: Color) -> some View {
        let cap = 5_000_000.0
        let progress = min(1, bps / cap)
        return VStack(spacing: 6) {
            RingView(progress: isPaused ? 0 : progress,
                     tint: isPaused ? Color.secondary : tint,
                     lineWidth: 7) {
                VStack(spacing: 0) {
                    Image(systemName: symbol)
                        .font(.system(size: 11, weight: .semibold))
                    Text(Format.speed(bps))
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                }
                .foregroundStyle(isPaused ? Color.secondary : tint)
            }
            .frame(width: 74, height: 74)
            Text(direction)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            Text(Format.bytes(usage))
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
        }
    }

    // MARK: Speed test — the one place this app makes an actual network
    // request, and only when you tap the button.

    @ViewBuilder
    private var speedTestSection: some View {
        switch model.speedTestStage {
        case .idle:
            if model.isNetworkAvailable {
                Button {
                    model.startSpeedTest()
                } label: {
                    Label("Test Speed", systemImage: "speedometer")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.blue)
                .controlSize(.regular)
            } else {
                noConnectionNotice
            }

        case .ping, .download, .upload:
            HStack(spacing: 10) {
                ProgressView()
                    .controlSize(.small)
                Text(speedTestStageLabel)
                    .font(.system(size: 12, weight: .medium))
                Spacer()
                Button("Cancel") { model.cancelSpeedTest() }
                    .buttonStyle(.borderless)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(Tokens.cardBackground)
            )

        case .done(let result):
            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    speedResultChip(symbol: "arrow.down.circle.fill",
                                     value: String(format: "%.0f", result.downloadMbps),
                                     unit: "Mbps ↓", tint: .blue)
                    speedResultChip(symbol: "arrow.up.circle.fill",
                                     value: String(format: "%.0f", result.uploadMbps),
                                     unit: "Mbps ↑", tint: .green)
                    speedResultChip(symbol: "waveform.path.ecg",
                                     value: String(format: "%.0f", result.pingMs),
                                     unit: "ms ping", tint: .orange)
                }
                Button {
                    model.startSpeedTest()
                } label: {
                    Label("Test Again", systemImage: "arrow.clockwise")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(.blue)
                .controlSize(.small)
            }

        case .failed:
            if model.isNetworkAvailable {
                VStack(spacing: 8) {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Text("Speed test failed — check your connection.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    Button {
                        model.startSpeedTest()
                    } label: {
                        Label("Retry", systemImage: "arrow.clockwise")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(.orange)
                    .controlSize(.small)
                }
            } else {
                noConnectionNotice
            }
        }
    }

    /// Distinct from a generic test failure — this is what it looks like
    /// when the Mac itself has no usable network path at all, checked live
    /// via `NWPathMonitor` rather than assumed from the test result alone.
    private var noConnectionNotice: some View {
        HStack(spacing: 6) {
            Image(systemName: "wifi.slash")
                .foregroundStyle(.secondary)
            Text("No network connection available.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Tokens.cardBackground)
        )
    }

    private var speedTestStageLabel: String {
        switch model.speedTestStage {
        case .ping: return "Checking latency…"
        case .download: return "Testing download…"
        case .upload: return "Testing upload…"
        default: return ""
        }
    }

    private func speedResultChip(symbol: String, value: String, unit: String, tint: Color) -> some View {
        VStack(spacing: 3) {
            Image(systemName: symbol)
                .font(.system(size: 12))
                .foregroundStyle(tint)
            Text(value)
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundStyle(tint)
                .monospacedDigit()
            Text(unit)
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(tint.opacity(0.08))
        )
    }

    // MARK: By Wi-Fi network

    private var wifiList: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("By Wi-Fi network")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
            if model.perNetworkLocationDenied {
                Text("Location access is off — enable it in Settings to see this.")
                    .font(.caption2)
                    .foregroundStyle(.orange)
            } else if model.perNetworkUsageTotals.isEmpty {
                Text("No network history yet.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else {
                // Already sorted largest-first; the popover only needs a
                // glance, so the full breakdown stays in Settings.
                ForEach(model.perNetworkUsageTotals.prefix(4), id: \.name) { entry in
                    networkRow(entry, isCurrent: entry.name == model.currentNetworkLabel)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Every row opens the same place — macOS's own Wi-Fi settings, not this
    /// app's — regardless of whether it's the network you're on right now or
    /// not; the "now" badge is informational only, not a different kind of row.
    private func networkRow(_ entry: (name: String, received: Int, sent: Int), isCurrent: Bool) -> some View {
        Button {
            openWiFiSettings()
        } label: {
            HStack() {
                Image(systemName: networkSymbol(for: entry.name))
                    .padding(.horizontal, entry.name == "Other network" ? 4 : 0)
                    .font(.system(size: 10))
                    .foregroundStyle(isCurrent ? Color.green : Color.secondary)
                Text(entry.name)
                    .font(.system(size: 11, weight: isCurrent ? .semibold : .regular))
                    .lineLimit(1)
                if isCurrent {
                    Text("now")
                        .font(.system(size: 8, weight: .bold))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(Color.green.opacity(0.18)))
                        .foregroundStyle(Color.green)
                }
                Spacer()
                Text(Format.bytes(entry.received + entry.sent))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isCurrent ? Color.green.opacity(0.08) : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .help("Open Wi-Fi settings")
    }

    /// "Other network" is a fallback bucket (wired, VPN-only, or an
    /// unreadable SSID) rather than a real Wi-Fi network — giving it the
    /// same wifi glyph as everything else would claim a signal that isn't
    /// there.
    private func networkSymbol(for name: String) -> String {
        name == "Other network" ? "cable.connector" : "wifi"
    }

    private var enablePerNetworkHint: some View {
        HStack(spacing: 6) {
            Image(systemName: "wifi")
                .foregroundStyle(.secondary)
            Text("Turn on \"By Wi-Fi network\" in Settings to see usage per network.")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Spacer()
        }
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: 16) {
            Button {
                openSettings()
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 12))
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .help("Settings")
            .accessibilityLabel("Settings")

            Spacer()

            // While paused, `pausedNotice` above already has its own
            // prominent Resume Network Mode button — repeating the same
            // action here too was just clutter, so this slot only appears
            // when there's something to quit.
            if !isPaused {
                Button {
                    pause()
                } label: {
                    footerLabel("Quit Network Mode", symbol: "pause.circle")
                }
                .buttonStyle(.borderless)
                .help("Quit network mode — stops tracking, leaves break reminders untouched")
            }
        }
        .foregroundStyle(.secondary)
    }

    private func footerLabel(_ title: String, symbol: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: symbol)
            Text(title)
        }
        .font(.system(size: 11, weight: .medium))
        .foregroundColor(Color(nsColor: .secondaryLabelColor))
    }

    // MARK: Actions

    private func pause() {
        var copy = model.settings
        copy.networkTrackingEnabled = false
        model.settings = copy
    }

    private func resume() {
        var copy = model.settings
        copy.networkTrackingEnabled = true
        model.settings = copy
    }

    private func openSettings() {
        model.pendingSettingsTab = 5
        model.onOpenSettings?()
    }

    /// Deep-links to macOS's own Wi-Fi pane — not this app's Settings. Same
    /// URL scheme Control Center's own "Wi-Fi Settings…" link uses.
    private func openWiFiSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.wifi-settings") else { return }
        NSWorkspace.shared.open(url)
    }
}
