import AppKit
import Combine
import Foundation

// MARK: - The model

final class AppModel: ObservableObject {

    // Persisted preferences.
    @Published var settings: Settings = .default {
        didSet { settingsDidChange(from: oldValue) }
    }

    // Live state.
    @Published var now = Date()
    @Published var launchAtLoginProblem: String?
    /// Bytes/sec, refreshed every tick - drives the popover's live speed.
    @Published var downloadSpeedBps: Double = 0
    @Published var uploadSpeedBps: Double = 0
    @Published var perNetworkLocationDenied = false
    @Published var perNetworkUsageTotals: [(name: String, received: Int, sent: Int)] = []
    @Published var allTimeNetworkTotal: (received: Int, sent: Int) = (0, 0)
    /// The network currently attributed for usage - kept live every tick
    /// (not just when bytes moved) so the "connected now" marker in the
    /// usage list never lags behind an actual network change.
    @Published var currentNetworkLabel: String?
    @Published var speedTestStage: SpeedTestStage = .idle
    /// Live Mbps readings during an in-progress speed test - only meaningful
    /// while `speedTestStage` is `.download`/`.upload`; each holds its last
    /// reading once that stage finishes, so the popover's rings can freeze
    /// on the just-measured number rather than snapping back to zero.
    @Published var speedTestDownloadLiveMbps: Double = 0
    @Published var speedTestUploadLiveMbps: Double = 0
    @Published var isNetworkAvailable = true

    // Derived stats, refreshed rather than recomputed on every read.
    @Published var todayStat = DayStat(day: StatsStore.key(for: Date()))

    /// Set by the app delegate so views can open the Settings window.
    var onOpenSettings: (() -> Void)?

    private let stats = StatsStore()
    private var timer: Timer?
    private var wifiMonitor: WiFiMonitor?
    private let speedTestService = SpeedTestService()
    private var reachability: NetworkReachability?
    private var suppressSideEffects = false
    private var lastNetworkTotals: (received: Int, sent: Int)?
    private var networkTicksSinceSave = 0
    private var budgetAlertDay: String?

    init() {
        suppressSideEffects = true
        settings = SettingsStore.load()
        suppressSideEffects = false
        refreshDerived()
    }

    // MARK: - Lifecycle

    func start() {
        suppressSideEffects = true
        settings.launchAtLogin = LaunchAtLogin.isEnabled
        suppressSideEffects = false

        updateWiFiMonitor()
        reachability = NetworkReachability { [weak self] available in
            DispatchQueue.main.async { self?.isNetworkAvailable = available }
        }

        let t = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.tick()
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
        tick()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        reachability?.stop()
        stats.save()
    }

    // MARK: - Wi-Fi (per-network usage)

    private func updateWiFiMonitor() {
        guard settings.perNetworkUsageEnabled else {
            wifiMonitor = nil
            perNetworkLocationDenied = false
            return
        }
        guard wifiMonitor == nil else { return }
        perNetworkLocationDenied = false
        let monitor = WiFiMonitor(onAuthorizationDenied: { [weak self] in
            self?.perNetworkLocationDenied = true
        })
        wifiMonitor = monitor
        monitor.requestAccess()
    }

    // MARK: - Tick

    private func tick() {
        let previousDay = StatsStore.key(for: now)
        now = Date()
        updateNetworkUsage()
        // Roll the derived figures over at midnight even if nothing moved.
        if StatsStore.key(for: now) != previousDay { refreshDerived() }
    }

    // MARK: - Network

    private func updateNetworkUsage() {
        guard settings.networkTrackingEnabled else {
            downloadSpeedBps = 0
            uploadSpeedBps = 0
            currentNetworkLabel = nil
            return
        }
        currentNetworkLabel = settings.perNetworkUsageEnabled
            ? (wifiMonitor?.currentNetworkLabel() ?? "Other network")
            : nil

        let totals = NetworkMonitor.currentTotals()
        defer { lastNetworkTotals = totals }
        guard let previous = lastNetworkTotals else { return }

        let deltaReceived = totals.received - previous.received
        let deltaSent = totals.sent - previous.sent
        // A negative delta means an interface reset (Wi-Fi toggled, VPN
        // reconnected) - skip rather than let usage go backwards.
        guard deltaReceived >= 0, deltaSent >= 0 else {
            downloadSpeedBps = 0
            uploadSpeedBps = 0
            return
        }
        // One tick is one second, so the delta *is* the current bytes/sec.
        downloadSpeedBps = Double(deltaReceived)
        uploadSpeedBps = Double(deltaSent)
        guard deltaReceived + deltaSent > 0 else { return }

        let networkLabel = currentNetworkLabel

        let updated = stats.update(now) { stat in
            stat.bytesReceived += deltaReceived
            stat.bytesSent += deltaSent
            if let networkLabel {
                stat.perNetworkReceived[networkLabel, default: 0] += deltaReceived
                stat.perNetworkSent[networkLabel, default: 0] += deltaSent
            }
        }
        // Today's totals drive the menu bar and the popover rings, so keep
        // them live every tick; the heavier all-history sums wait for a save.
        todayStat = updated
        checkDataBudget()

        networkTicksSinceSave += 1
        if networkTicksSinceSave >= 30 {
            networkTicksSinceSave = 0
            stats.save()
            refreshDerived()
        }
    }

    private func checkDataBudget() {
        guard settings.dailyDataLimitMB > 0 else { return }
        let today = stats.today(now)
        let usedMB = (today.bytesReceived + today.bytesSent) / 1_000_000
        guard usedMB >= settings.dailyDataLimitMB else { return }

        let key = StatsStore.key(for: now)
        guard budgetAlertDay != key else { return }
        budgetAlertDay = key

        NotificationManager.shared.post(
            title: "Data budget reached",
            body: "You've used \(Format.bytes(today.bytesReceived + today.bytesSent)) today - your daily budget is \(Format.bytes(settings.dailyDataLimitMB * 1_000_000))."
        )
    }

    /// This week's / this month's network usage, summed from daily history.
    func networkTotal(lastDays: Int) -> (received: Int, sent: Int) {
        (stats.total({ $0.bytesReceived }, lastDays: lastDays, from: now),
         stats.total({ $0.bytesSent }, lastDays: lastDays, from: now))
    }

    /// Whichever period the menu bar icon is set to show.
    var menuBarUsageTotal: (received: Int, sent: Int) {
        switch settings.menuBarUsagePeriod {
        case .day: return (todayStat.bytesReceived, todayStat.bytesSent)
        case .week: return networkTotal(lastDays: 7)
        case .month: return networkTotal(lastDays: 30)
        }
    }

    // MARK: - Speed test

    func startSpeedTest() {
        speedTestDownloadLiveMbps = 0
        speedTestUploadLiveMbps = 0
        speedTestService.run(onStageChange: { [weak self] stage in
            DispatchQueue.main.async {
                self?.speedTestStage = stage
            }
        }, onProgress: { [weak self] mbps in
            // Already delivered on the main queue by the service's timer.
            guard let self else { return }
            switch self.speedTestStage {
            case .download: self.speedTestDownloadLiveMbps = mbps
            case .upload: self.speedTestUploadLiveMbps = mbps
            default: break
            }
        })
    }

    func cancelSpeedTest() {
        speedTestService.cancel()
        speedTestStage = .idle
        speedTestDownloadLiveMbps = 0
        speedTestUploadLiveMbps = 0
    }

    // MARK: - Stats actions

    /// Clears every day's tracked usage (totals and the per-network
    /// breakdown). Tracking itself keeps running right after.
    func resetNetworkUsage() {
        stats.eraseAll()
        refreshDerived()
    }

    func restoreDefaultSettings() {
        settings = .default
    }

    private func refreshDerived() {
        todayStat = stats.today(now)
        allTimeNetworkTotal = stats.allTimeNetworkTotal()
        perNetworkUsageTotals = stats.perNetworkTotals()
    }

    // MARK: - Settings side effects

    private func settingsDidChange(from old: Settings) {
        guard !suppressSideEffects else { return }

        if old.launchAtLogin != settings.launchAtLogin {
            launchAtLoginProblem = LaunchAtLogin.set(settings.launchAtLogin)
        }
        if old.perNetworkUsageEnabled != settings.perNetworkUsageEnabled {
            updateWiFiMonitor()
        }
        if !old.networkTrackingEnabled && settings.networkTrackingEnabled {
            // Resuming: don't credit everything that moved while paused to
            // the first tick back.
            lastNetworkTotals = nil
        }

        SettingsStore.save(settings)
    }
}
