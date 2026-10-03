import Foundation

enum HelperConstants {
    static let appIdentifier = "com.proxyme.app"
    static let helperIdentifier = "com.proxyme.app.helper"
    static let coreIdentifier = "com.proxyme.app.sing-box"
    static let machServiceName = "com.proxyme.app.helper"
    static let daemonPlistName = "com.proxyme.app.helper.plist"
    /// Bump whenever the helper's behaviour or XPC interface changes so the app
    /// can ask a stale, still-running helper to exit and be relaunched.
    static let helperVersion = "1"

    static let tunAddress = "172.19.0.1/30"
    static let tunAddress6 = "fdfe:dcba:9876::1/126"
    /// Peer address inside the TUN subnet. Pointing system DNS here forces lookups
    /// into the tunnel, where they are hijacked — LAN resolvers would bypass it.
    static let tunDNSAddress = "172.19.0.2"
}

@objc protocol HelperProtocol {
    func version(reply: @escaping (String) -> Void)
    /// Validates `config` with the core, then starts the tunnel. `error` is nil on success.
    /// With `overrideDNS`, system DNS is pointed into the tunnel until it stops.
    func start(config: Data, overrideDNS: Bool, reply: @escaping (_ error: String?) -> Void)
    func stop(reply: @escaping () -> Void)
    func status(reply: @escaping (_ running: Bool) -> Void)
    /// Returns log bytes starting at `offset` and the offset to pass next time.
    func readLog(from offset: UInt64, reply: @escaping (Data, UInt64) -> Void)
    /// Stops the tunnel and exits the helper process; launchd restarts it on demand.
    func quit(reply: @escaping () -> Void)
}
