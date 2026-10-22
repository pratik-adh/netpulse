import AppKit
import SwiftUI
import Combine

/// Owns the menu bar item: the usage readout, the popover and the
/// right-click menu. It's the app's only way in - there's no Dock icon and
/// no main window - so it never hides itself: paused, it shows a pause glyph,
/// and with the readout turned off it shows a bare icon.
final class NetworkStatusItemController: NSObject, NSPopoverDelegate {

    private let model: AppModel
    private let statusItem: NSStatusItem
    private let popover = NSPopover()
    private let content: NSHostingController<NetworkPopoverView>
    private var cancellables = Set<AnyCancellable>()
    private var buttonWindowObservers: [NSObjectProtocol] = []

    /// The menu bar total only changes in whole units the formatter actually
    /// shows (e.g. "1.2MB" holds steady across many one-second ticks), so
    /// skip re-rendering the attributed title - the costly part of
    /// `refresh()` - when the visible text and state haven't moved.
    private enum RenderedState: Equatable {
        case glyph(symbol: String, tooltip: String)
        case text(title: String, tooltip: String)
    }
    private var lastRenderedState: RenderedState?

    init(model: AppModel) {
        self.model = model
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        content = NSHostingController(rootView: NetworkPopoverView(model: model))
        content.sizingOptions = [.preferredContentSize]
        super.init()

        popover.behavior = .transient
        popover.animates = true
        popover.contentViewController = content
        popover.delegate = self

        if let button = statusItem.button {
            button.target = self
            button.action = #selector(handleClick(_:))
            _ = button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.imageScaling = .scaleProportionallyDown

            // The button's own width tracks its content (the readout grows
            // from "340KB" to "1.2GB", or collapses to a bare pause glyph),
            // which slides its window sideways as the menu bar repacks -
            // watch for that so an open popover stays anchored.
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

        if !model.settings.networkTrackingEnabled {
            // Paused - show a pause glyph instead of vanishing, so the icon
            // (and any open popover) stays anchored and the app stays reachable.
            showGlyph("pause.circle", on: button, accessibility: "Netpulse paused", tooltip: "Netpulse - paused")
            return
        }

        let tooltipText = tooltip
        guard model.settings.showUsageInMenuBar else {
            showGlyph("waveform.path.ecg", on: button, accessibility: "Netpulse", tooltip: tooltipText)
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

        // The formatted total (and its tooltip) often hold steady for many
        // consecutive ticks - only rebuild the attributed title, which costs
        // a regex scan and font-range lookup, when what's on screen would
        // actually change.
        let state = RenderedState.text(title: text, tooltip: tooltipText)
        guard lastRenderedState != state else { return }
        lastRenderedState = state

        // No leading icon next to the readout - with the arrows already
        // carrying the up/down meaning, a glyph would be purely decorative.
        // The title uses a fully monospaced font (not just tabular digits)
        // so the unit letters (B/K/M/G) and arrows advance by the same width
        // too, not just the numbers.
        button.image = nil
        button.imagePosition = .noImage
        let font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        let smallFont = NSFont.monospacedSystemFont(ofSize: 10, weight: .regular)

        let attributedTitle = NSMutableAttributedString(
            string: text,
            attributes: [.font: font]
        )

        // `range(of:)` only ever finds the *first* match, which is why the
        // upload figure kept its unit at full size when up/down are shown
        // separately (two units in the string, e.g. "↓ 1.2MB ↑ 340KB") -
        // enumerate every match instead so each one gets the small font.
        let pattern = "KB|MB|GB|TB"
        if let regex = try? NSRegularExpression(pattern: pattern) {
            let fullRange = NSRange(text.startIndex..., in: text)
            for match in regex.matches(in: text, range: fullRange) {
                attributedTitle.addAttribute(.font, value: smallFont, range: match.range)
            }
        }

        button.attributedTitle = attributedTitle
        button.toolTip = tooltipText
    }

    private func showGlyph(_ symbol: String, on button: NSStatusBarButton, accessibility: String, tooltip: String) {
        let state = RenderedState.glyph(symbol: symbol, tooltip: tooltip)
        guard lastRenderedState != state else { return }
        lastRenderedState = state
        let config = NSImage.SymbolConfiguration(pointSize: 13, weight: .medium)
        let icon = NSImage(systemSymbolName: symbol, accessibilityDescription: accessibility)?
            .withSymbolConfiguration(config)
        icon?.isTemplate = true
        button.image = icon
        button.attributedTitle = NSAttributedString(string: "")
        button.imagePosition = .imageOnly
        button.toolTip = tooltip
    }

    private var tooltip: String {
        let today = model.todayStat
        var lines = ["Netpulse - ↓ \(Format.bytes(today.bytesReceived))  ↑ \(Format.bytes(today.bytesSent)) today"]
        let week = model.networkTotal(lastDays: 7)
        lines.append("This week: \(Format.bytes(week.received + week.sent))")
        return lines.joined(separator: "\n")
    }

    /// `NSPopover.show(relativeTo:of:)` only positions the popover the first
    /// time - calling it again while already shown is a no-op - so when the
    /// button's width changes under an open popover, slide the popover's own
    /// window by the same horizontal delta instead, keeping its arrow lined
    /// up with the button's new center.
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

    /// Fires however the popover closed - an explicit `performClose(nil)`
    /// above, or (since it's `.transient`) AppKit dismissing it on an
    /// outside click, which never goes through `closePopover()` at all. A
    /// finished or in-flight speed test only means something while you're
    /// looking at it, so either way this clears it back to idle rather than
    /// leaving a stale result (or a test still quietly running) for the next
    /// time the popover opens.
    func popoverDidClose(_ notification: Notification) {
        guard model.speedTestStage != .idle else { return }
        model.cancelSpeedTest()
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

        // "Pause", not "Quit", because this toggle is fully reversible with
        // one click - the word "Quit" is reserved for the one action that
        // actually ends the process.
        if model.settings.networkTrackingEnabled {
            menu.addItem(item("Pause tracking", #selector(pauseNetwork)))
        } else {
            menu.addItem(item("Resume tracking", #selector(resumeNetwork)))
        }

        menu.addItem(.separator())
        menu.addItem(item("Settings…", #selector(openSettings), ","))
        menu.addItem(item("Quit Netpulse", #selector(quit), "q"))

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

    @objc private func openSettings() { model.onOpenSettings?() }
    @objc private func quit() { NSApp.terminate(nil) }

    deinit {
        for observer in buttonWindowObservers {
            NotificationCenter.default.removeObserver(observer)
        }
    }
}
