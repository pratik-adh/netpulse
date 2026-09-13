import Network
import Foundation

/// Whether the Mac currently has a usable network path — used only to show
/// a clear "no connection available" state for the speed test, instead of
/// a generic failure. `NWPathMonitor` is a local system read: no permission
/// prompt, no network request of its own.
final class NetworkReachability {
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.downtime.mac.reachability")

    init(onChange: @escaping (Bool) -> Void) {
        monitor.pathUpdateHandler = { path in
            onChange(path.status == .satisfied)
        }
        monitor.start(queue: queue)
    }

    func stop() {
        monitor.cancel()
    }
}
