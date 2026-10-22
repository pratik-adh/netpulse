import Foundation

enum Format {

    /// Reused rather than built fresh each call - this runs every second off
    /// the menu bar's live network total, and constructing a `ByteCountFormatter`
    /// is real, avoidable work to repeat that often. Only ever touched from
    /// the main thread, so a plain shared instance is safe.
    private static let byteCountFormatter: ByteCountFormatter = {
        let f = ByteCountFormatter()
        f.countStyle = .file
        f.allowedUnits = [.useKB, .useMB, .useGB, .useTB]
        return f
    }()

    /// "1.2GB" / "340MB" - for usage totals.
    static func bytes(_ count: Int) -> String {
        byteCountFormatter.string(fromByteCount: Int64(max(0, count))).replacingOccurrences(of: " ", with: "")
    }

    /// "1.2M" / "340K" / "0B" - no space, for the popover's rings.
    static func speed(_ bytesPerSecond: Double) -> String {
        let units = ["B", "K", "M", "G"]
        var value = max(0, bytesPerSecond)
        var index = 0
        while value >= 1024 && index < units.count - 1 {
            value /= 1024
            index += 1
        }
        if index == 0 { return "\(Int(value))\(units[index])" }
        return String(format: "%.1f%@", value, units[index])
    }
}
