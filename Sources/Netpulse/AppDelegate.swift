import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {

    private let model = AppModel()
    private var statusItem: NetworkStatusItemController?
    private var settingsWindow: SettingsWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        settingsWindow = SettingsWindowController(model: model)
        statusItem = NetworkStatusItemController(model: model)

        model.onOpenSettings = { [weak self] in
            self?.statusItem?.closePopover()
            self?.settingsWindow?.show()
        }

        if model.settings.dailyDataLimitMB > 0 {
            NotificationManager.shared.requestAuthorizationIfNeeded()
        }

        model.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        model.stop()
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        true
    }
}
