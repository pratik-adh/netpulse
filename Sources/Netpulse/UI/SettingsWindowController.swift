import AppKit
import SwiftUI

/// Keeps a single Settings window alive for the life of the app.
final class SettingsWindowController: NSObject, NSWindowDelegate {

    private var window: NSWindow?
    private let model: AppModel

    init(model: AppModel) {
        self.model = model
        super.init()
    }

    func show() {
        if let window {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            return
        }

        let hosting = NSHostingController(rootView: SettingsView(model: model))
        hosting.sizingOptions = [.preferredContentSize]
        let newWindow = NSWindow(contentViewController: hosting)
        newWindow.title = "Netpulse Settings"
        newWindow.styleMask = [.titled, .closable, .miniaturizable]
        newWindow.isReleasedWhenClosed = false
        newWindow.delegate = self
        // Size to what the view actually asks for. Hard-coding the tab content
        // size left no room for the tab bar, which clipped it against the
        // title bar.
        hosting.view.layoutSubtreeIfNeeded()
        let fitting = hosting.view.fittingSize
        newWindow.setContentSize(fitting.width > 1 && fitting.height > 1
                                 ? fitting
                                 : NSSize(width: 584, height: 544))
        newWindow.center()
        newWindow.level = .normal
        window = newWindow

        NSApp.activate(ignoringOtherApps: true)
        newWindow.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        // Let the accessory app drop back out of the way.
        DispatchQueue.main.async {
            NSApp.setActivationPolicy(.accessory)
        }
    }
}
