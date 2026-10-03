import Foundation
import Darwin

/// Owns the root-side sing-box process. All state is confined to `queue`.
final class TunnelRunner {
    static let shared = TunnelRunner()

    private let queue = DispatchQueue(label: "com.proxyme.helper.runner")
    private var process: Process?

    private let supportDir = URL(fileURLWithPath: "/Library/Application Support/ProxyMe", isDirectory: true)
    private var coreURL: URL { supportDir.appendingPathComponent("sing-box") }
    private var configURL: URL { supportDir.appendingPathComponent("config.json") }
    private var logURL: URL { supportDir.appendingPathComponent("sing-box.log") }
    private var pidURL: URL { supportDir.appendingPathComponent("sing-box.pid") }
    private var dnsBackupURL: URL { supportDir.appendingPathComponent("dns-backup.json") }

    private static let maxLogChunk = 256 * 1024

    // MARK: - Public API

    func start(config: Data, overrideDNS: Bool, completion: @escaping (String?) -> Void) {
        queue.async { completion(self.startLocked(config: config, overrideDNS: overrideDNS)) }
    }

    /// Cleans up after a previous helper instance that died mid-session.
    func recover() {
        queue.async {
            self.killOrphan()
            SystemDNS.restore(backupURL: self.dnsBackupURL)
        }
    }

    func stop(completion: @escaping () -> Void) {
        queue.async {
            self.stopLocked()
            completion()
        }
    }

    func stopSync() {
        queue.sync { self.stopLocked() }
    }

    func isRunning(completion: @escaping (Bool) -> Void) {
        queue.async { completion(self.process?.isRunning ?? false) }
    }

    func readLog(from offset: UInt64, completion: @escaping (Data, UInt64) -> Void) {
        queue.async {
            guard let handle = try? FileHandle(forReadingFrom: self.logURL) else {
                completion(Data(), 0)
                return
            }
            defer { try? handle.close() }
            let size = (try? handle.seekToEnd()) ?? 0
            // The log is truncated on every start; restart from the top if it shrank.
            var start = offset > size ? 0 : offset
            if size - start > UInt64(Self.maxLogChunk) {
                start = size - UInt64(Self.maxLogChunk)
            }
            try? handle.seek(toOffset: start)
            let data = (try? handle.readToEnd()) ?? Data()
            completion(data, start + UInt64(data.count))
        }
    }

    // MARK: - Lifecycle

    private func startLocked(config: Data, overrideDNS: Bool) -> String? {
        stopLocked()
        do {
            try prepareSupportDirectory()
            killOrphan()
            try installCore()
            try writePrivate(config, to: configURL)
        } catch let error as RunnerError {
            return error.message
        } catch {
            return error.localizedDescription
        }

        if let problem = checkConfig() {
            return "Invalid configuration:\n\(problem)"
        }

        guard writeEmptyPrivateFile(at: logURL),
              let logHandle = try? FileHandle(forWritingTo: logURL) else {
            return "Could not open the log file."
        }

        let proc = Process()
        proc.executableURL = coreURL
        proc.arguments = ["run", "-c", configURL.path, "-D", supportDir.path]
        proc.standardInput = FileHandle.nullDevice
        proc.standardOutput = logHandle
        proc.standardError = logHandle
        proc.terminationHandler = { [weak self] proc in
            self?.queue.async { self?.coreDidExit(proc) }
        }
        do {
            try proc.run()
        } catch {
            return "Could not launch the proxy core: \(error.localizedDescription)"
        }
        try? logHandle.close()
        process = proc
        try? writePrivate(Data("\(proc.processIdentifier)".utf8), to: pidURL)

        // Give the core a moment to fail fast (bad interface, port in use, ...).
        Thread.sleep(forTimeInterval: 1.2)
        if !proc.isRunning {
            process = nil
            try? FileManager.default.removeItem(at: pidURL)
            return "The proxy core exited immediately:\n\(logTail())"
        }
        if overrideDNS {
            SystemDNS.apply(server: HelperConstants.tunDNSAddress, backupURL: dnsBackupURL)
        }
        return nil
    }

    /// The core died on its own; undo the DNS override so the system keeps resolving.
    private func coreDidExit(_ proc: Process) {
        guard process === proc else { return }
        process = nil
        try? FileManager.default.removeItem(at: pidURL)
        SystemDNS.restore(backupURL: dnsBackupURL)
    }

    private func stopLocked() {
        guard let proc = process else { return }
        process = nil
        SystemDNS.restore(backupURL: dnsBackupURL)
        if proc.isRunning {
            // SIGTERM lets sing-box remove its routes and the TUN interface.
            proc.terminate()
            let deadline = Date().addingTimeInterval(5)
            while proc.isRunning && Date() < deadline {
                Thread.sleep(forTimeInterval: 0.05)
            }
            if proc.isRunning {
                kill(proc.processIdentifier, SIGKILL)
            }
        }
        try? FileManager.default.removeItem(at: pidURL)
    }

    /// Terminates a core left behind by a helper that died without cleaning up.
    private func killOrphan() {
        guard let text = try? String(contentsOf: pidURL, encoding: .utf8),
              let pid = pid_t(text.trimmingCharacters(in: .whitespacesAndNewlines)), pid > 1 else { return }
        defer { try? FileManager.default.removeItem(at: pidURL) }
        var buffer = [CChar](repeating: 0, count: 4096)
        guard proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0,
              String(cString: buffer) == coreURL.path else { return }
        kill(pid, SIGTERM)
        let deadline = Date().addingTimeInterval(5)
        while kill(pid, 0) == 0 && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.05)
        }
        if kill(pid, 0) == 0 {
            kill(pid, SIGKILL)
        }
    }

    // MARK: - Files

    private func prepareSupportDirectory() throws {
        let attributes: [FileAttributeKey: Any] = [
            .posixPermissions: 0o755, .ownerAccountID: 0, .groupOwnerAccountID: 0,
        ]
        let fm = FileManager.default
        var isDir: ObjCBool = false
        if fm.fileExists(atPath: supportDir.path, isDirectory: &isDir) {
            let type = try fm.attributesOfItem(atPath: supportDir.path)[.type] as? FileAttributeType
            guard isDir.boolValue, type == .typeDirectory else {
                throw RunnerError("\(supportDir.path) is not a directory.")
            }
            try fm.setAttributes(attributes, ofItemAtPath: supportDir.path)
        } else {
            try fm.createDirectory(at: supportDir, withIntermediateDirectories: false, attributes: attributes)
        }
    }

    /// Copies the bundled core into the root-owned support directory and verifies the
    /// copy's signature, so a binary swapped inside the (user-writable) app bundle can
    /// never be executed as root.
    private func installCore() throws {
        guard let requirement = CodeSigning.requirement(identifier: HelperConstants.coreIdentifier) else {
            throw RunnerError("The helper is not signed with a team identity.")
        }
        guard let helperURL = Bundle.main.executableURL?.resolvingSymlinksInPath() else {
            throw RunnerError("Could not locate the helper executable.")
        }
        let bundled = helperURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Helpers/sing-box")
        let fm = FileManager.default
        let staging = supportDir.appendingPathComponent("sing-box.new")
        try? fm.removeItem(at: staging)
        do {
            try fm.copyItem(at: bundled, to: staging)
            try fm.setAttributes(
                [.posixPermissions: 0o755, .ownerAccountID: 0, .groupOwnerAccountID: 0],
                ofItemAtPath: staging.path)
        } catch {
            throw RunnerError("Could not install the proxy core: \(error.localizedDescription)")
        }
        guard CodeSigning.verify(fileAt: staging, requirement: requirement) else {
            try? fm.removeItem(at: staging)
            throw RunnerError("The bundled proxy core failed signature verification.")
        }
        try? fm.removeItem(at: coreURL)
        try fm.moveItem(at: staging, to: coreURL)
    }

    private func writeEmptyPrivateFile(at url: URL) -> Bool {
        try? FileManager.default.removeItem(at: url)
        return FileManager.default.createFile(
            atPath: url.path, contents: nil, attributes: [.posixPermissions: 0o600])
    }

    private func writePrivate(_ data: Data, to url: URL) throws {
        guard writeEmptyPrivateFile(at: url) else {
            throw RunnerError("Could not create \(url.lastPathComponent).")
        }
        try data.write(to: url)
    }

    private func checkConfig() -> String? {
        let proc = Process()
        proc.executableURL = coreURL
        proc.arguments = ["check", "-c", configURL.path, "-D", supportDir.path]
        let pipe = Pipe()
        proc.standardInput = FileHandle.nullDevice
        proc.standardOutput = pipe
        proc.standardError = pipe
        do {
            try proc.run()
        } catch {
            return error.localizedDescription
        }
        let output = pipe.fileHandleForReading.readDataToEndOfFile()
        proc.waitUntilExit()
        guard proc.terminationStatus != 0 else { return nil }
        let text = String(decoding: output, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? "sing-box check failed (\(proc.terminationStatus))." : text
    }

    private func logTail() -> String {
        guard let data = try? Data(contentsOf: logURL) else { return "" }
        return String(decoding: data.suffix(2000), as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private struct RunnerError: Error {
    let message: String
    init(_ message: String) { self.message = message }
}
