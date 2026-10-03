import Foundation

/// Translates a profile + settings into a sing-box configuration.
enum ConfigBuilder {
    private static let proxyTag = "proxy"
    private static let directTag = "direct"
    private static let remoteDNSTag = "dns-remote"
    private static let localDNSTag = "dns-local"

    /// `localResolver` is the pre-connect system DNS server; needed when system DNS is
    /// pointed into the tunnel, where the `local` resolver would loop back into itself.
    static func build(profile: ProxyProfile, settings: AppSettings, localResolver: String? = nil) throws -> Data {
        let (bypassDomains, bypassCIDRs) = splitBypass(settings.bypassEntries)

        let config: [String: Any] = [
            "log": ["level": settings.logLevel.rawValue, "timestamp": true],
            "dns": dns(settings: settings, bypassDomains: bypassDomains, localResolver: localResolver),
            "inbounds": inbounds(settings: settings),
            "outbounds": [outbound(for: profile), ["type": "direct", "tag": directTag]],
            "route": route(profile: profile, settings: settings,
                           bypassDomains: bypassDomains, bypassCIDRs: bypassCIDRs),
        ]
        return try JSONSerialization.data(withJSONObject: config, options: [.prettyPrinted, .sortedKeys])
    }

    // MARK: - Sections

    private static func dns(settings: AppSettings, bypassDomains: [String],
                            localResolver: String?) -> [String: Any] {
        let local: [String: Any] = settings.overridesSystemDNS
            ? ["type": "udp", "tag": localDNSTag, "server": localResolver ?? "1.1.1.1"]
            : ["type": "local", "tag": localDNSTag]
        guard let address = settings.dns.address else {
            return ["servers": [local], "final": localDNSTag]
        }
        // DoH over the proxy: works for TCP-only proxies and keeps lookups off the local network.
        let remote: [String: Any] = [
            "type": "https", "tag": remoteDNSTag, "server": address, "detour": proxyTag,
        ]
        var dns: [String: Any] = ["servers": [remote, local], "final": remoteDNSTag]
        if !bypassDomains.isEmpty {
            dns["rules"] = [["domain_suffix": bypassDomains, "server": localDNSTag]]
        }
        return dns
    }

    private static func inbounds(settings: AppSettings) -> [[String: Any]] {
        var inbounds: [[String: Any]] = [[
            "type": "tun",
            "tag": "tun-in",
            "address": [HelperConstants.tunAddress, HelperConstants.tunAddress6],
            "auto_route": true,
        ]]
        if settings.localProxyEnabled {
            inbounds.append([
                "type": "mixed",
                "tag": "mixed-in",
                "listen": "127.0.0.1",
                "listen_port": settings.localProxyPort,
            ])
        }
        return inbounds
    }

    private static func route(profile: ProxyProfile, settings: AppSettings,
                              bypassDomains: [String], bypassCIDRs: [String]) -> [String: Any] {
        var rules: [[String: Any]] = [
            ["action": "sniff"],
            [
                "type": "logical", "mode": "or",
                "rules": [["protocol": "dns"], ["port": 53]],
                "action": "hijack-dns",
            ],
        ]
        if !bypassDomains.isEmpty {
            rules.append(["domain_suffix": bypassDomains, "outbound": directTag])
        }
        if !bypassCIDRs.isEmpty {
            rules.append(["ip_cidr": bypassCIDRs, "outbound": directTag])
        }
        if settings.bypassLAN {
            rules.append(["ip_is_private": true, "outbound": directTag])
        }
        if !profile.kind.supportsUDP {
            // Fail UDP (QUIC etc.) fast so apps fall back to TCP instead of timing out.
            rules.append(["network": "udp", "action": "reject"])
        }
        return [
            "rules": rules,
            "final": proxyTag,
            "auto_detect_interface": true,
            "default_domain_resolver": localDNSTag,
        ]
    }

    // MARK: - Outbound

    static func outbound(for p: ProxyProfile) -> [String: Any] {
        var out: [String: Any] = [
            "tag": proxyTag,
            "server": p.host.trimmingCharacters(in: .whitespaces),
            "server_port": p.port,
        ]
        switch p.kind {
        case .socks5, .socks4, .socks4a:
            out["type"] = "socks"
            out["version"] = p.kind == .socks5 ? "5" : (p.kind == .socks4 ? "4" : "4a")
            if !p.username.isEmpty { out["username"] = p.username }
            if p.kind == .socks5 && !p.password.isEmpty { out["password"] = p.password }
        case .http, .https:
            out["type"] = "http"
            if !p.username.isEmpty {
                out["username"] = p.username
                out["password"] = p.password
            }
        case .shadowsocks:
            out["type"] = "shadowsocks"
            out["method"] = p.method
            out["password"] = p.password
        case .trojan:
            out["type"] = "trojan"
            out["password"] = p.password
        case .vmess:
            out["type"] = "vmess"
            out["uuid"] = p.uuid
            out["security"] = "auto"
            out["alter_id"] = 0
        case .vless:
            out["type"] = "vless"
            out["uuid"] = p.uuid
            if !p.flow.isEmpty { out["flow"] = p.flow }
        case .hysteria2:
            out["type"] = "hysteria2"
            out["password"] = p.password
        }
        if p.usesTLS {
            out["tls"] = tls(for: p)
        }
        if p.kind.supportsTransport, let transport = transport(for: p) {
            out["transport"] = transport
        }
        return out
    }

    private static func tls(for p: ProxyProfile) -> [String: Any] {
        var tls: [String: Any] = ["enabled": true]
        if !p.sni.isEmpty { tls["server_name"] = p.sni }
        if p.allowInsecure { tls["insecure"] = true }
        let reality = p.kind == .vless && !p.realityPublicKey.isEmpty
        if reality {
            tls["reality"] = [
                "enabled": true, "public_key": p.realityPublicKey, "short_id": p.realityShortID,
            ]
        }
        // REALITY requires uTLS; QUIC-based Hysteria2 can't use it.
        if p.kind != .hysteria2, reality || !p.fingerprint.isEmpty {
            tls["utls"] = ["enabled": true, "fingerprint": p.fingerprint.isEmpty ? "chrome" : p.fingerprint]
        }
        return tls
    }

    private static func transport(for p: ProxyProfile) -> [String: Any]? {
        switch p.transport {
        case .tcp:
            return nil
        case .ws:
            var ws: [String: Any] = ["type": "ws", "path": p.transportPath.isEmpty ? "/" : p.transportPath]
            if !p.transportHost.isEmpty { ws["headers"] = ["Host": p.transportHost] }
            return ws
        case .grpc:
            return ["type": "grpc", "service_name": p.transportPath]
        }
    }

    // MARK: - Bypass list

    /// Splits user entries into domain suffixes and IP/CIDR ranges.
    static func splitBypass(_ entries: [String]) -> (domains: [String], cidrs: [String]) {
        var domains: [String] = []
        var cidrs: [String] = []
        for entry in entries {
            if isIPOrCIDR(entry) {
                cidrs.append(entry)
            } else {
                var domain = entry.lowercased()
                if domain.hasPrefix("*.") { domain.removeFirst(2) }
                if domain.hasPrefix(".") { domain.removeFirst() }
                if !domain.isEmpty { domains.append(domain) }
            }
        }
        return (domains, cidrs)
    }

    private static func isIPOrCIDR(_ entry: String) -> Bool {
        let parts = entry.split(separator: "/", maxSplits: 1)
        guard let address = parts.first.map(String.init) else { return false }
        var v4 = in_addr()
        var v6 = in6_addr()
        let isV4 = inet_pton(AF_INET, address, &v4) == 1
        let isV6 = !isV4 && inet_pton(AF_INET6, address, &v6) == 1
        guard isV4 || isV6 else { return false }
        if parts.count == 2 {
            guard let prefix = Int(parts[1]), (0...(isV4 ? 32 : 128)).contains(prefix) else { return false }
        }
        return true
    }
}
