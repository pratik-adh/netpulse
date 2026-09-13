import Darwin
import Foundation

/// Reads cumulative bytes sent/received across the Mac's network interfaces
/// since boot — the same BSD interface counters Activity Monitor's network
/// tab and tools like `nettop`/`netstat -ib` read. No special permission is
/// needed, and there's no per-app breakdown: that needs a privileged packet
/// filter or a Network Extension, well outside what an unprivileged,
/// unsandboxed app can do.
enum NetworkMonitor {

    /// Loopback traffic (127.0.0.1) isn't "internet usage"; everything else
    /// (Wi-Fi, Ethernet, VPN tunnels, AirDrop) is counted.
    private static let ignoredInterface = "lo0"

    static func currentTotals() -> (received: Int, sent: Int) {
        var mib: [Int32] = [CTL_NET, PF_ROUTE, 0, AF_LINK, NET_RT_IFLIST2, 0]
        var len = 0
        guard sysctl(&mib, u_int(mib.count), nil, &len, nil, 0) == 0, len > 0 else {
            return (0, 0)
        }
        var buffer = [UInt8](repeating: 0, count: len)
        guard sysctl(&mib, u_int(mib.count), &buffer, &len, nil, 0) == 0 else {
            return (0, 0)
        }

        var received = 0
        var sent = 0
        var nameBuffer = [CChar](repeating: 0, count: Int(IF_NAMESIZE))

        buffer.withUnsafeBytes { raw in
            var offset = 0
            while offset + MemoryLayout<if_msghdr2>.size <= len {
                let header = raw.load(fromByteOffset: offset, as: if_msghdr2.self)
                guard header.ifm_msglen > 0 else { break }
                if header.ifm_type == UInt8(RTM_IFINFO2) {
                    let name: String = nameBuffer.withUnsafeMutableBufferPointer { buf in
                        guard let base = buf.baseAddress,
                              if_indextoname(UInt32(header.ifm_index), base) != nil
                        else { return "" }
                        return String(cString: base)
                    }
                    if name != ignoredInterface {
                        received += Int(header.ifm_data.ifi_ibytes)
                        sent += Int(header.ifm_data.ifi_obytes)
                    }
                }
                offset += Int(header.ifm_msglen)
            }
        }
        return (received, sent)
    }
}
