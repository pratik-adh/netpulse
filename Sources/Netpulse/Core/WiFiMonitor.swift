import CoreLocation
import CoreWLAN
import Foundation

/// The current Wi-Fi network's name, used only to label network usage by
/// network in the Network tab. macOS requires Location Services authorization
/// to read a Wi-Fi SSID at all — a restriction Apple added because a SSID can
/// reveal where you are, not something this app has any way around.
final class WiFiMonitor: NSObject, CLLocationManagerDelegate {

    private let locationManager = CLLocationManager()
    private let wifiClient = CWWiFiClient.shared()
    private let onAuthorizationDenied: () -> Void

    private(set) var isAuthorized = false

    init(onAuthorizationDenied: @escaping () -> Void) {
        self.onAuthorizationDenied = onAuthorizationDenied
        super.init()
        locationManager.delegate = self
    }

    func requestAccess() {
        switch locationManager.authorizationStatus {
        case .authorized, .authorizedAlways:
            isAuthorized = true
        case .notDetermined:
            locationManager.requestAlwaysAuthorization()
        default:
            isAuthorized = false
            onAuthorizationDenied()
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .authorized, .authorizedAlways:
            isAuthorized = true
        case .notDetermined:
            break
        default:
            isAuthorized = false
            onAuthorizationDenied()
        }
    }

    /// The current Wi-Fi network's name, or `nil` if it can't be determined
    /// (no permission, no active Wi-Fi interface). Wired/Ethernet connections
    /// have no SSID to report — the caller labels those separately.
    func currentNetworkLabel() -> String? {
        guard isAuthorized else { return nil }
        guard let ssid = wifiClient.interface()?.ssid(), !ssid.isEmpty else { return nil }
        return ssid
    }
}
