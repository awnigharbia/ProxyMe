import Foundation
import SystemConfiguration

enum SystemResolver {
    /// First usable system DNS server, ignoring our own tunnel override.
    static func primaryServer() -> String? {
        guard let dict = SCDynamicStoreCopyValue(nil, "State:/Network/Global/DNS" as CFString) as? [String: Any],
              let servers = dict["ServerAddresses"] as? [String] else { return nil }
        return servers.first { !$0.contains("%") && $0 != HelperConstants.tunDNSAddress }
    }
}
