import Foundation
import ServiceManagement
import AppKit

/// "Open at Login" with a fallback.
///
/// `SMAppService` is the modern API, but it needs a properly bundled (ideally
/// signed) app. When it refuses - which happens with ad-hoc local builds - we
/// fall back to writing a plain LaunchAgent, which always works.
enum LaunchAtLogin {

    private static let label = "com.netpulse.mac.launcher"

    private static var agentURL: URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home
            .appendingPathComponent("Library/LaunchAgents", isDirectory: true)
            .appendingPathComponent("\(label).plist")
    }

    static var isEnabled: Bool {
        if SMAppService.mainApp.status == .enabled { return true }
        return FileManager.default.fileExists(atPath: agentURL.path)
    }

    /// Returns nil on success, or a short human-readable problem.
    @discardableResult
    static func set(_ enabled: Bool) -> String? {
        // Try the system API first.
        do {
            if enabled {
                if SMAppService.mainApp.status != .enabled {
                    try SMAppService.mainApp.register()
                }
                removeAgent()
                return nil
            } else {
                if SMAppService.mainApp.status == .enabled {
                    try SMAppService.mainApp.unregister()
                }
                removeAgent()
                return nil
            }
        } catch {
            // Fall back to a LaunchAgent.
            if enabled {
                return writeAgent()
            } else {
                removeAgent()
                return nil
            }
        }
    }

    // MARK: - LaunchAgent fallback

    private static func writeAgent() -> String? {
        let executable = Bundle.main.executablePath ?? ProcessInfo.processInfo.arguments.first
        guard let executable else { return "Couldn't work out where Netpulse is installed." }

        let plist: [String: Any] = [
            "Label": label,
            "ProgramArguments": [executable],
            "RunAtLoad": true,
            "KeepAlive": false,
            "ProcessType": "Interactive"
        ]

        do {
            let dir = agentURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let data = try PropertyListSerialization.data(fromPropertyList: plist,
                                                          format: .xml,
                                                          options: 0)
            try data.write(to: agentURL, options: .atomic)
            return nil
        } catch {
            return "Couldn't write the login item: \(error.localizedDescription)"
        }
    }

    private static func removeAgent() {
        try? FileManager.default.removeItem(at: agentURL)
    }
}
