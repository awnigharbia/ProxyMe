import Foundation
import Darwin

/// Points every active network service's DNS at the tunnel and restores the
/// previous servers afterwards. The original values are persisted first so a
/// crash or reboot can never leave the system with a dead resolver.
enum SystemDNS {
    private static let networksetup = "/usr/sbin/networksetup"

    static func apply(server: String, backupURL: URL) {
        restore(backupURL: backupURL)
        var backup: [String: [String]] = [:]
        for service in activeServices() {
            // A lingering tunnel address means an earlier restore was missed; treat as unset.
            backup[service] = dnsServers(for: service).filter { $0 != server }
        }
        guard !backup.isEmpty,
              let data = try? JSONEncoder().encode(backup),
              (try? data.write(to: backupURL, options: .atomic)) != nil else { return }
        for service in backup.keys {
            run(networksetup, ["-setdnsservers", service, server])
        }
        flushCache()
    }

    static func restore(backupURL: URL) {
        guard let data = try? Data(contentsOf: backupURL),
              let backup = try? JSONDecoder().decode([String: [String]].self, from: data) else { return }
        for (service, servers) in backup {
            run(networksetup, ["-setdnsservers", service] + (servers.isEmpty ? ["Empty"] : servers))
        }
        try? FileManager.default.removeItem(at: backupURL)
        flushCache()
    }

    private static func activeServices() -> [String] {
        // First line is a legend; disabled services are prefixed with "*".
        run(networksetup, ["-listallnetworkservices"])
            .split(whereSeparator: \.isNewline)
            .dropFirst()
            .map(String.init)
            .filter { !$0.hasPrefix("*") && !$0.isEmpty }
    }

    private static func dnsServers(for service: String) -> [String] {
        // Prints a sentence instead of addresses when nothing is configured.
        run(networksetup, ["-getdnsservers", service])
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter(isIPAddress)
    }

    private static func isIPAddress(_ text: String) -> Bool {
        var v4 = in_addr()
        var v6 = in6_addr()
        return inet_pton(AF_INET, text, &v4) == 1 || inet_pton(AF_INET6, text, &v6) == 1
    }

    private static func flushCache() {
        run("/usr/bin/dscacheutil", ["-flushcache"])
        run("/usr/bin/killall", ["-HUP", "mDNSResponder"])
    }

    @discardableResult
    private static func run(_ path: String, _ arguments: [String]) -> String {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: path)
        proc.arguments = arguments
        let pipe = Pipe()
        proc.standardInput = FileHandle.nullDevice
        proc.standardOutput = pipe
        proc.standardError = FileHandle.nullDevice
        guard (try? proc.run()) != nil else { return "" }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        proc.waitUntilExit()
        return String(decoding: data, as: UTF8.self)
    }
}
