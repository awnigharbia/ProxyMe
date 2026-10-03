import Foundation
import ServiceManagement

struct HelperError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

/// App-side handle on the privileged helper: installation state + XPC calls.
final class HelperClient: @unchecked Sendable {
    enum InstallState {
        case notRegistered, requiresApproval, enabled
    }

    private let service = SMAppService.daemon(plistName: HelperConstants.daemonPlistName)
    private let lock = NSLock()
    private var connection: NSXPCConnection?

    var installState: InstallState {
        switch service.status {
        case .enabled: .enabled
        case .requiresApproval: .requiresApproval
        default: .notRegistered
        }
    }

    func register() throws {
        try service.register()
    }

    func unregister() async throws {
        resetConnection()
        try await service.unregister()
    }

    func openApprovalSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }

    // MARK: - Calls

    func version() async throws -> String {
        try await call { helper, done in helper.version { done(.success($0)) } }
    }

    func start(config: Data, overrideDNS: Bool) async throws {
        let problem: String? = try await call { helper, done in
            helper.start(config: config, overrideDNS: overrideDNS) { done(.success($0)) }
        }
        if let problem { throw HelperError(problem) }
    }

    func stop() async throws {
        let _: Bool = try await call { helper, done in helper.stop { done(.success(true)) } }
    }

    func isRunning() async throws -> Bool {
        try await call { helper, done in helper.status { done(.success($0)) } }
    }

    func readLog(from offset: UInt64) async throws -> (Data, UInt64) {
        try await call { helper, done in helper.readLog(from: offset) { done(.success(($0, $1))) } }
    }

    /// Asks an outdated helper to exit; launchd starts the current binary on next use.
    func quit() async throws {
        let _: Bool = try await call { helper, done in helper.quit { done(.success(true)) } }
        resetConnection()
    }

    // MARK: - Connection

    private func call<T>(
        _ body: @escaping (HelperProtocol, @escaping (Result<T, Error>) -> Void) -> Void
    ) async throws -> T {
        let connection = currentConnection()
        return try await withCheckedThrowingContinuation { continuation in
            // XPC guarantees exactly one of the error handler or the reply runs.
            let proxy = connection.remoteObjectProxyWithErrorHandler { error in
                continuation.resume(throwing: HelperError("Could not reach the helper: \(error.localizedDescription)"))
            }
            guard let helper = proxy as? HelperProtocol else {
                continuation.resume(throwing: HelperError("Could not reach the helper."))
                return
            }
            body(helper) { continuation.resume(with: $0) }
        }
    }

    private func currentConnection() -> NSXPCConnection {
        lock.lock()
        defer { lock.unlock() }
        if let connection { return connection }
        let new = NSXPCConnection(machServiceName: HelperConstants.machServiceName, options: .privileged)
        new.remoteObjectInterface = NSXPCInterface(with: HelperProtocol.self)
        // Refuse to talk to anything but our own signed helper.
        if let requirement = CodeSigning.requirement(identifier: HelperConstants.helperIdentifier) {
            new.setCodeSigningRequirement(requirement)
        }
        new.invalidationHandler = { [weak self, weak new] in
            guard let self else { return }
            self.lock.lock()
            if self.connection === new { self.connection = nil }
            self.lock.unlock()
        }
        new.resume()
        connection = new
        return new
    }

    private func resetConnection() {
        lock.lock()
        let old = connection
        connection = nil
        lock.unlock()
        old?.invalidate()
    }
}
