import AppKit
import SwiftUI

/// A color that resolves differently depending on which appearance - light or
/// dark - is currently drawing, instead of relying on one value's opacity to
/// read the same against opposite backgrounds (it won't: the same translucent
/// white that reads as a soft highlight on a dark window reads as almost
/// nothing on a white one).
func adaptiveColor(light: NSColor, dark: NSColor) -> Color {
    Color(NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
    })
}

/// Shared surface colors for the popover and settings chrome. Tuned
/// separately per appearance rather than as one opacity over `.primary` -
/// dark mode already read fine as a faint highlight on a near-black window;
/// light mode needs a visibly darker, more solid-looking fill to read as a
/// card at all against white.
enum Tokens {
    /// Row and card fills - the speed test's progress and notice cards.
    static let cardBackground = adaptiveColor(
        light: NSColor(white: 0.0, alpha: 0.08),
        dark: NSColor(white: 1.0, alpha: 0.05)
    )

    /// The popover's own backing. Drawn explicitly rather than left to
    /// whatever the system's default popover chrome happens to render -
    /// which read as a dim, slightly gray sheet rather than a clean light
    /// surface once the system was in Light Mode.
    static let popoverBackground = adaptiveColor(
        light: NSColor(white: 1.0, alpha: 1.0),
        dark: NSColor(white: 0.145, alpha: 1.0)
    )
}
