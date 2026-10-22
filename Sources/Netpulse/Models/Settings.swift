import Foundation

/// Which period the menu bar's total-usage text shows.
enum NetworkMenuBarPeriod: String, Codable, CaseIterable, Identifiable {
    case day
    case week
    case month

    var id: String { rawValue }

    var title: String {
        switch self {
        case .day: return "Today's usage"
        case .week: return "This week's usage"
        case .month: return "This month's usage"
        }
    }
}

struct Settings: Codable, Equatable {

    // MARK: Tracking

    /// The master switch - also what "Pause" in the menu and popover flips.
    var networkTrackingEnabled: Bool
    /// Daily budget in MB before a one-time nudge notification fires. 0 = off.
    /// This is a nudge, not an enforced limit - actually blocking traffic
    /// needs a Network Extension entitlement this app doesn't have.
    var dailyDataLimitMB: Int
    /// Breaks down usage by Wi-Fi network name. Off by default - reading the
    /// current SSID needs Location Services, a real macOS permission prompt.
    var perNetworkUsageEnabled: Bool

    // MARK: Menu bar

    /// Whether the usage total sits in the menu bar. Off leaves a bare icon -
    /// the item itself never disappears, since it's the app's only way in.
    var showUsageInMenuBar: Bool
    /// Which period's total that readout shows. Live up/down *speed* lives
    /// in the popover instead (opened by clicking the icon) - the
    /// always-visible menu bar text shows a total, not a rate, so it stays
    /// meaningful at a glance rather than flickering every tick.
    var menuBarUsagePeriod: NetworkMenuBarPeriod
    /// Totals as two figures (↓ / ↑) instead of one combined figure.
    var showUploadDownloadSeparately: Bool

    // MARK: Login

    var launchAtLogin: Bool

    // MARK: - Presets

    /// MB. 0 = no budget.
    static let dataLimitChoices: [Int] = [0, 500, 1000, 2000, 5000, 10000, 20000]

    static var `default`: Settings {
        Settings(
            networkTrackingEnabled: true,
            dailyDataLimitMB: 0,
            perNetworkUsageEnabled: false,
            showUsageInMenuBar: true,
            menuBarUsagePeriod: .day,
            showUploadDownloadSeparately: true,
            launchAtLogin: false
        )
    }

    /// Snaps a value onto the nearest option a picker actually offers, so a
    /// settings file from another build can never leave a picker blank.
    /// Compared in `Double` so an absurd decoded value saturates rather than
    /// trapping on integer overflow.
    private static func snap(_ value: Int, to choices: [Int]) -> Int {
        let target = Double(value)
        let best = choices.min(by: { abs(Double($0) - target) < abs(Double($1) - target) })
        return best ?? value
    }

    mutating func normalize() {
        dailyDataLimitMB = Settings.snap(dailyDataLimitMB, to: Settings.dataLimitChoices)
    }

    // MARK: - Forgiving decoding
    //
    // Every key falls back to the default, so a settings file written by an
    // older or newer build of Netpulse still loads instead of being thrown away.

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Settings.default
        networkTrackingEnabled = (try? c.decode(Bool.self, forKey: .networkTrackingEnabled)) ?? d.networkTrackingEnabled
        dailyDataLimitMB = (try? c.decode(Int.self, forKey: .dailyDataLimitMB)) ?? d.dailyDataLimitMB
        perNetworkUsageEnabled = (try? c.decode(Bool.self, forKey: .perNetworkUsageEnabled)) ?? d.perNetworkUsageEnabled
        showUsageInMenuBar = (try? c.decode(Bool.self, forKey: .showUsageInMenuBar)) ?? d.showUsageInMenuBar
        menuBarUsagePeriod = (try? c.decode(NetworkMenuBarPeriod.self, forKey: .menuBarUsagePeriod)) ?? d.menuBarUsagePeriod
        showUploadDownloadSeparately = (try? c.decode(Bool.self, forKey: .showUploadDownloadSeparately)) ?? d.showUploadDownloadSeparately
        launchAtLogin = (try? c.decode(Bool.self, forKey: .launchAtLogin)) ?? d.launchAtLogin
        normalize()
    }

    init(networkTrackingEnabled: Bool,
         dailyDataLimitMB: Int,
         perNetworkUsageEnabled: Bool,
         showUsageInMenuBar: Bool,
         menuBarUsagePeriod: NetworkMenuBarPeriod,
         showUploadDownloadSeparately: Bool,
         launchAtLogin: Bool) {
        self.networkTrackingEnabled = networkTrackingEnabled
        self.dailyDataLimitMB = dailyDataLimitMB
        self.perNetworkUsageEnabled = perNetworkUsageEnabled
        self.showUsageInMenuBar = showUsageInMenuBar
        self.menuBarUsagePeriod = menuBarUsagePeriod
        self.showUploadDownloadSeparately = showUploadDownloadSeparately
        self.launchAtLogin = launchAtLogin
    }
}

// MARK: - Persistence

enum SettingsStore {
    private static let key = "netpulse.settings.v1"

    static func load() -> Settings {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode(Settings.self, from: data)
        else {
            return .default
        }
        return decoded
    }

    static func save(_ settings: Settings) {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}
