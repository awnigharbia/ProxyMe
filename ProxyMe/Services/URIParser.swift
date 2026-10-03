import Foundation

/// Parses share links (socks5://, http://, ss://, trojan://, vless://, vmess://, hysteria2://).
enum URIParser {
    static func parseAll(_ text: String) -> [ProxyProfile] {
        text.split(whereSeparator: { $0.isNewline || $0 == " " })
            .compactMap { parse(String($0)) }
    }

    static func parse(_ raw: String) -> ProxyProfile? {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let scheme = text.split(separator: ":", maxSplits: 1).first?.lowercased(),
              text.contains("://") else { return nil }
        let profile: ProxyProfile?
        switch scheme {
        case "socks5", "socks5h", "socks": profile = parseBasic(text, kind: .socks5)
        case "socks4": profile = parseBasic(text, kind: .socks4)
        case "socks4a": profile = parseBasic(text, kind: .socks4a)
        case "http": profile = parseBasic(text, kind: .http)
        case "https": profile = parseBasic(text, kind: .https)
        case "ss": profile = parseShadowsocks(text)
        case "trojan": profile = parseTrojan(text)
        case "vless": profile = parseVLESS(text)
        case "vmess": profile = parseVMess(text)
        case "hysteria2", "hy2": profile = parseHysteria2(text)
        default: profile = nil
        }
        guard let profile, profile.validationError == nil else { return nil }
        return profile
    }

    // MARK: - Per scheme

    private static func parseBasic(_ text: String, kind: ProxyKind) -> ProxyProfile? {
        guard let c = URLComponents(string: text), let host = c.host, !host.isEmpty else { return nil }
        var p = base(kind: kind, components: c, host: host)
        p.username = c.user ?? ""
        p.password = c.password ?? ""
        // Some tools emit socks5://base64(user:pass)@host:port.
        if p.password.isEmpty, !p.username.isEmpty, kind == .socks5,
           let decoded = decodeBase64(p.username), let split = splitOnce(decoded, ":") {
            p.username = split.0
            p.password = split.1
        }
        return p
    }

    private static func parseShadowsocks(_ text: String) -> ProxyProfile? {
        // SIP002: ss://base64(method:password)@host:port#name
        if let c = URLComponents(string: text), let host = c.host, !host.isEmpty, let user = c.user {
            var p = base(kind: .shadowsocks, components: c, host: host)
            if let password = c.password {
                p.method = user
                p.password = password
            } else if let decoded = decodeBase64(user), let split = splitOnce(decoded, ":") {
                p.method = split.0
                p.password = split.1
            } else {
                return nil
            }
            return p
        }
        // Legacy: ss://base64(method:password@host:port)#name
        var body = String(text.dropFirst("ss://".count))
        var name = ""
        if let hash = body.firstIndex(of: "#") {
            name = String(body[body.index(after: hash)...]).removingPercentEncoding ?? ""
            body = String(body[..<hash])
        }
        guard let decoded = decodeBase64(body),
              let c = URLComponents(string: "ss://" + decoded), let host = c.host,
              let at = decoded.lastIndex(of: "@"),
              let split = splitOnce(String(decoded[..<at]), ":") else { return nil }
        var p = base(kind: .shadowsocks, components: c, host: host)
        p.name = name
        p.method = split.0
        p.password = split.1
        return p
    }

    private static func parseTrojan(_ text: String) -> ProxyProfile? {
        guard let c = URLComponents(string: text), let host = c.host, !host.isEmpty else { return nil }
        var p = base(kind: .trojan, components: c, host: host)
        p.password = c.user ?? ""
        applyCommonQuery(query(c), to: &p)
        return p
    }

    private static func parseVLESS(_ text: String) -> ProxyProfile? {
        guard let c = URLComponents(string: text), let host = c.host, !host.isEmpty else { return nil }
        var p = base(kind: .vless, components: c, host: host)
        p.uuid = c.user ?? ""
        let q = query(c)
        let security = q["security"] ?? "none"
        p.tls = security == "tls" || security == "reality"
        p.flow = q["flow"] ?? ""
        if security == "reality" {
            p.realityPublicKey = q["pbk"] ?? ""
            p.realityShortID = q["sid"] ?? ""
        }
        applyCommonQuery(q, to: &p)
        return p
    }

    private static func parseVMess(_ text: String) -> ProxyProfile? {
        let body = String(text.dropFirst("vmess://".count))
        guard let decoded = decodeBase64(body), let data = decoded.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        func string(_ key: String) -> String {
            if let s = json[key] as? String { return s }
            if let n = json[key] as? NSNumber { return n.stringValue }
            return ""
        }
        var p = ProxyProfile()
        p.kind = .vmess
        p.name = string("ps")
        p.host = string("add")
        p.port = Int(string("port")) ?? ProxyKind.vmess.defaultPort
        p.uuid = string("id")
        p.tls = string("tls") == "tls"
        p.sni = string("sni")
        p.fingerprint = string("fp")
        switch string("net") {
        case "ws":
            p.transport = .ws
            p.transportPath = string("path")
            p.transportHost = string("host")
        case "grpc":
            p.transport = .grpc
            p.transportPath = string("path")
        default:
            break
        }
        return p
    }

    private static func parseHysteria2(_ text: String) -> ProxyProfile? {
        guard let c = URLComponents(string: text), let host = c.host, !host.isEmpty else { return nil }
        var p = base(kind: .hysteria2, components: c, host: host)
        p.password = [c.user, c.password].compactMap { $0 }.joined(separator: ":")
        let q = query(c)
        p.sni = q["sni"] ?? ""
        p.allowInsecure = q["insecure"] == "1"
        return p
    }

    // MARK: - Helpers

    private static func base(kind: ProxyKind, components c: URLComponents, host: String) -> ProxyProfile {
        var p = ProxyProfile()
        p.kind = kind
        // URLComponents keeps the brackets on IPv6 literals.
        p.host = host.trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
        p.port = c.port ?? kind.defaultPort
        p.name = c.fragment ?? ""
        return p
    }

    private static func query(_ c: URLComponents) -> [String: String] {
        var result: [String: String] = [:]
        for item in c.queryItems ?? [] { result[item.name] = item.value ?? "" }
        return result
    }

    /// TLS + transport parameters shared by Trojan and VLESS links.
    private static func applyCommonQuery(_ q: [String: String], to p: inout ProxyProfile) {
        p.sni = q["sni"] ?? q["peer"] ?? ""
        p.fingerprint = q["fp"] ?? ""
        p.allowInsecure = q["allowInsecure"] == "1" || q["insecure"] == "1"
        switch q["type"] {
        case "ws":
            p.transport = .ws
            p.transportPath = q["path"] ?? ""
            p.transportHost = q["host"] ?? ""
        case "grpc":
            p.transport = .grpc
            p.transportPath = q["serviceName"] ?? ""
        default:
            break
        }
    }

    private static func splitOnce(_ text: String, _ separator: Character) -> (String, String)? {
        guard let index = text.firstIndex(of: separator) else { return nil }
        return (String(text[..<index]), String(text[text.index(after: index)...]))
    }

    private static func decodeBase64(_ text: String) -> String? {
        var s = (text.removingPercentEncoding ?? text)
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while s.count % 4 != 0 { s.append("=") }
        guard let data = Data(base64Encoded: s) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
