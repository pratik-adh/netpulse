import AppKit
import SwiftUI
import Combine

/// A second, independent status item for network usage - deliberately kept
/// separate from the break-reminder icon so the two features read "at a
/// glance" as distinct things, and so pausing one never touches the other.
///
/// This item fully disappears when network tracking is off. That's safe here
/// (unlike the break icon) because the break status item is always present
/// as the app's one guaranteed way back in - Settings and Quit live there
/// too, so hiding *this* icon never leaves the app unreachable.
final class NetworkStatusItemController: NSObject {

    private let model: AppModel
    private let statusItem: NSStatusItem
    private let popover = NSPopover()
    private let content: NSHostingController<NetworkPopoverView>
    private var cancellables = Set<AnyCancellable>()
    private var buttonWindowObservers: [NSObjectProtocol] = []

    init(model: AppModel) {
        self.model = model
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        content = NSHostingController(rootView: NetworkPopoverView(model: model))
        content.sizingOptions = [.preferredContentSize]
        super.init()

        popover.behavior = .transient
        popover.animates = true
        popover.contentViewController = content

        if let button = statusItem.button {
            button.target = self
            button.action = #selector(handleClick(_:))
            _ = button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.imageScaling = .scaleProportionallyDown

            // Mirrors the break status item: the button's own width tracks
            // its content, which slides its window sideways as the menu bar
            // repacks - watch for that so an open popover stays anchored.
            if let window = button.window {
                let names: [Notification.Name] = [NSWindow.didResizeNotification, NSWindow.didMoveNotification]
                buttonWindowObservers = names.map { name in
                    NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                        guard let self, self.popover.isShown else { return }
                        self.recenterOpenPopover(on: button)
                    }
                }
            }
        }

        model.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.refresh() }
            .store(in: &cancellables)

        refresh()
    }

    // MARK: - Appearance

    private func refresh() {
        guard let button = statusItem.button else { return }

        guard model.settings.showNetworkSpeedInMenuBar else {
            statusItem.isVisible = false
            return
        }

        let networkPaused = !model.settings.networkTrackingEnabled
        let breaksPaused = model.isManuallyPaused

        // Both features paused at once: the break icon already shows a
        // single pause glyph, so this one steps aside rather than showing a
        // second, redundant one right beside it. If a popover happened to be
        // open when the second pause landed, close it too - otherwise it's
        // left floating with no icon to anchor to.
        if networkPaused && breaksPaused {
            statusItem.isVisible = false
            closePopover()
            return
        }

        statusItem.isVisible = true

        if networkPaused {
            // Just network is paused - show its own pause glyph instead of
            // vanishing, so the icon (and any open popover) stays anchored,
            // the same way the break icon never fully disappears either.
            let config = NSImage.SymbolConfiguration(pointSize: 13, weight: .medium)
            let icon = NSImage(systemSymbolName: "pause.circle", accessibilityDescription: "Network paused")?
                .withSymbolConfiguration(config)
            icon?.isTemplate = true
            button.image = icon
            button.attributedTitle = NSAttributedString(string: "")
            button.imagePosition = .imageOnly
            button.toolTip = "Network - paused"
            return
        }

        // A total, not a live rate: the menu bar reads at a glance without
        // flickering every second, and stays meaningful when you're not
        // looking right at it. Live up/down *speed* lives one click away,
        // in the popover's hero rings, instead.
        let total = model.menuBarUsageTotal
        let text = model.settings.showUploadDownloadSeparately
            ? "↓ \(Format.bytes(total.received)) ↑ \(Format.bytes(total.sent))"
            : "↓↑ \(Format.bytes(total.received + total.sent))"

        // No status-item icon here (unlike the break item) - with the arrows
        // already carrying the up/down meaning, a leading glyph was purely
        // decorative. The title itself uses a fully monospaced font (not
        // just tabular digits) so the unit letters (B/K/M/G) and arrows
        // advance by the same width too, not just the numbers.
        button.image = nil
        button.imagePosition = .noImage
        let font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        let smallFont = NSFont.monospacedSystemFont(ofSize: 10, weight: .regular)

        let attributedTitle = NSMutableAttributedString(
            string: text,
            attributes: [.font: font]
        )

        let pattern = "KB|MB|GB|TB"

        if let range = text.range(of: pattern, options: .regularExpression) {
            attributedTitle.addAttribute(
                .font,
                value: smallFont,
                range: NSRange(range, in: text)
            )
        }

        button.attributedTitle = attributedTitle
        button.toolTip = tooltip
    }

    private var tooltip: String {
        let today = model.todayStat
        var lines = ["Network - ↓ \(Format.bytes(today.bytesReceived))  ↑ \(Format.bytes(today.bytesSent)) today"]
        let week = model.networkTotal(lastDays: 7)
        lines.append("This week: \(Format.bytes(week.received + week.sent))")
        return lines.joined(separator: "\n")
    }

    /// Same trick as the break status item: `NSPopover` only positions itself
    /// on first show, so slide its window manually when the button resizes.
    private func recenterOpenPopover(on button: NSStatusBarButton) {
        guard popover.isShown,
              let popoverWindow = popover.contentViewController?.view.window,
              let buttonWindow = button.window
        else { return }
        let buttonCenterX = buttonWindow.convertToScreen(button.convert(button.bounds, to: nil)).midX
        var frame = popoverWindow.frame
        frame.origin.x = (buttonCenterX - frame.width / 2).rounded()
        popoverWindow.setFrameOrigin(frame.origin)
    }

    // MARK: - Interaction

    @objc private func handleClick(_ sender: Any?) {
        let event = NSApp.currentEvent
        let isSecondary = event?.type == .rightMouseUp
            || event?.modifierFlags.contains(.control) == true
        if isSecondary {
            showMenu()
        } else {
            togglePopover()
        }
    }

    private func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
            return
        }
        NSApp.activate(ignoringOtherApps: true)
        sizeToFitContent()
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }

    private func sizeToFitContent() {
        content.view.layoutSubtreeIfNeeded()
        let fitting = content.view.fittingSize
        guard fitting.width > 1, fitting.height > 1 else { return }
        popover.contentSize = fitting
    }

    func closePopover() {
        if popover.isShown { popover.performClose(nil) }
    }

    private func showMenu() {
        let menu = NSMenu()
        let today = model.todayStat
        let status = NSMenuItem(
            title: "↓ \(Format.bytes(today.bytesReceived))  ↑ \(Format.bytes(today.bytesSent)) today",
            action: nil, keyEquivalent: ""
        )
        status.isEnabled = false
        menu.addItem(status)
        menu.addItem(.separator())

        if model.settings.networkTrackingEnabled {
            menu.addItem(item("Pause Network Mode", #selector(pauseNetwork)))
        } else {
            menu.addItem(item("Resume Network Mode", #selector(resumeNetwork)))
        }

        menu.addItem(.separator())
        // Deliberately no "Quit Downtime" here - this is a per-feature menu,
        // and quitting the app from it would take the break reminders down
        // too. The break icon's menu is the one place that actually quits.
        // "Pause", not "Quit", because this toggle is fully reversible with
        // one click - the word "Quit" is reserved for the one action that
        // actually ends the process.
        menu.addItem(item("Settings…", #selector(openSettings), ","))

        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    private func item(_ title: String, _ action: Selector, _ key: String = "") -> NSMenuItem {
        let entry = NSMenuItem(title: title, action: action, keyEquivalent: key)
        entry.target = self
        return entry
    }

    // MARK: - Menu actions

    @objc private func pauseNetwork() {
        var copy = model.settings
        copy.networkTrackingEnabled = false
        model.settings = copy
    }

    @objc private func resumeNetwork() {
        var copy = model.settings
        copy.networkTrackingEnabled = true
        model.settings = copy
    }

    @objc private func openSettings() {
        model.pendingSettingsTab = 1
        model.onOpenSettings?()
    }

    deinit {
        for observer in buttonWindowObservers {
            NotificationCenter.default.removeObserver(observer)
        }
    }
}
