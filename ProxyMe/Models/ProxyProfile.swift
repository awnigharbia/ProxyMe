import Foundation

enum ProxyKind: String, Codable, CaseIterable, Identifiable {
    case socks5, socks4, socks4a, http, https, shadowsocks, trojan, vmess, vless, hysteria2

    var id: String { rawValue }

    var title: String {
        switch self {
        case .socks5: "SOCKS5"
        case .socks4: "SOCKS4"
        case .socks4a: "SOCKS4a"
        case .http: "HTTP"
        case .https: "HTTPS"
        case .shadowsocks: "Shadowsocks"
        case .trojan: "Trojan"
        case .vmess: "VMess"
        case .vless: "VLESS"
        case .hysteria2: "Hysteria2"
        }
    }

    var defaultPort: Int {
        switch self {
        case .socks5, .socks4, .socks4a: 1080
        case .http: 8080
        case .shadowsocks: 8388
        case .https, .trojan, .vmess, .vless, .hysteria2: 443
        }
    }

    var usesUsername: Bool {
        switch self {
        case .socks5, .socks4, .socks4a, .http, .https: true
        default: false
        }
    }

    var usesPassword: Bool {
        switch self {
        case .socks5, .http, .https, .shadowsocks, .trojan, .hysteria2: true
        default: false
        }
    }

    var usesUUID: Bool { self == .vmess || self == .vless }

    /// TLS is always on for these; VMess/VLESS make it optional.
    var alwaysTLS: Bool { self == .https || self == .trojan || self == .hysteria2 }

    var supportsTLSOptions: Bool { alwaysTLS || usesUUID }

    var supportsTransport: Bool { self == .trojan || usesUUID }

    /// Whether UDP can be relayed through this proxy type.
    var supportsUDP: Bool {
        switch self {
        case .http, .https, .socks4, .socks4a: false
        default: true
        }
    }

    /// Hysteria2 runs over QUIC, so a TCP handshake can't measure it.
    var isTCPReachable: Bool { self != .hysteria2 }
}

enum TransportKind: String, Codable, CaseIterable, Identifiable {
    case tcp, ws, grpc

    var id: String { rawValue }

    var title: String {
        switch self {
        case .tcp: "TCP"
        case .ws: "WebSocket"
        case .grpc: "gRPC"
        }
    }
}

struct ProxyProfile: Identifiable, Codable, Hashable {
    var id = UUID()
    var name = ""
    var kind: ProxyKind = .socks5
    var host = ""
    var port = ProxyKind.socks5.defaultPort
    var username = ""
    var password = ""
    var uuid = ""
    /// Shadowsocks cipher.
    var method = "aes-256-gcm"
    /// Only consulted for VMess/VLESS; other kinds derive TLS from `kind.alwaysTLS`.
    var tls = false
    var sni = ""
    var allowInsecure = false
    var transport: TransportKind = .tcp
    /// WebSocket path or gRPC service name.
    var transportPath = ""
    /// WebSocket Host header.
    var transportHost = ""
    /// VLESS flow, e.g. xtls-rprx-vision.
    var flow = ""
    /// uTLS fingerprint, e.g. chrome.
    var fingerprint = ""
    var realityPublicKey = ""
    var realityShortID = ""

    var displayName: String {
        name.isEmpty ? (host.isEmpty ? "Untitled" : host) : name
    }

    var endpoint: String { host.isEmpty ? "—" : "\(host):\(port)" }

    var usesTLS: Bool { kind.alwaysTLS || (kind.usesUUID && tls) }

    /// Human-readable problem that prevents connecting, or nil when usable.
    var validationError: String? {
        if host.trimmingCharacters(in: .whitespaces).isEmpty { return "Server address is required." }
        if !(1...65535).contains(port) { return "Port must be between 1 and 65535." }
        if kind.usesUUID && UUID(uuidString: uuid) == nil { return "A valid UUID is required." }
        if [.shadowsocks, .trojan, .hysteria2].contains(kind) && password.isEmpty { return "Password is required." }
        if !realityPublicKey.isEmpty && kind != .vless { return "REALITY is only supported with VLESS." }
        return nil
    }

    static let shadowsocksMethods = [
        "aes-128-gcm", "aes-256-gcm", "chacha20-ietf-poly1305", "xchacha20-ietf-poly1305",
        "2022-blake3-aes-128-gcm", "2022-blake3-aes-256-gcm", "2022-blake3-chacha20-poly1305",
        "none",
    ]
}
