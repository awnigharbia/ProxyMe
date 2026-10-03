import Foundation

enum DNSPreset: String, Codable, CaseIterable, Identifiable {
    case cloudflare, google, quad9, system

    var id: String { rawValue }

    var title: String {
        switch self {
        case .cloudflare: "Cloudflare (DoH via proxy)"
        case .google: "Google (DoH via proxy)"
        case .quad9: "Quad9 (DoH via proxy)"
        case .system: "System DNS (direct, may leak)"
        }
    }

    /// DoH server address, nil for the system resolver.
    var address: String? {
        switch self {
        case .cloudflare: "1.1.1.1"
        case .google: "8.8.8.8"
        case .quad9: "9.9.9.9"
        case .system: nil
        }
    }
}

enum LogLevel: String, Codable, CaseIterable, Identifiable {
    case error, warn, info, debug

    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

struct AppSettings: Codable, Equatable {
    var bypassLAN = true
    /// One entry per line: domain suffixes (example.com) or IPs/CIDRs (10.0.0.0/8).
    var bypassList = ""
    var dns: DNSPreset = .cloudflare
    /// Point system DNS into the tunnel while connected so LAN resolvers can't bypass it.
    var overrideSystemDNS = true
    var localProxyEnabled = true
    var localProxyPort = 7890
    var logLevel: LogLevel = .info

    /// Overriding is pointless when lookups go to the system resolver anyway.
    var overridesSystemDNS: Bool { overrideSystemDNS && dns != .system }

    var bypassEntries: [String] {
        bypassList
            .split(whereSeparator: { $0.isNewline || $0 == "," })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") }
    }
}
