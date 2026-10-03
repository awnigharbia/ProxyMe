import Foundation
import Observation

@MainActor
@Observable
final class TunnelController {
    enum State: Equatable {
        case disconnected, connecting, connected, disconnecting
    }

    private(set) var state: State = .disconnected
    private(set) var lastError: String?
    private(set) var helperState: HelperClient.InstallState
    private(set) var logText = ""

    var isBusy: Bool { state == .connecting || state == .disconnecting }

    var statusText: String {
        switch state {
        case .disconnected: "Disconnected"
        case .connecting: "Connecting…"
        case .connected: "Connected"
        case .disconnecting: "Disconnecting…"
        }
    }

    private let store: ProfileStore
    private let helper = HelperClient()
    private var logOffset: UInt64 = 0
    private var pollTask: Task<Void, Never>?

    private static let maxLogLength = 120_000

    init(store: ProfileStore) {
        self.store = store
        helperState = helper.installState
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.poll()
                try? await Task.sleep(for: .seconds(3))
            }
        }
    }

    // MARK: - Actions

    func toggle() async {
        switch state {
        case .disconnected: await connect()
        case .connected: await disconnect()
        default: break
        }
    }

    func connect() async {
        guard state == .disconnected else { return }
        guard let profile = store.activeProfile else {
            lastError = "Add and select a proxy first."
            return
        }
        if let problem = profile.validationError {
            lastError = problem
            return
        }
        state = .connecting
        lastError = nil
        do {
            try await ensureHelper()
            let settings = store.settings
            let config = try ConfigBuilder.build(
                profile: profile, settings: settings, localResolver: SystemResolver.primaryServer())
            try await helper.start(config: config, overrideDNS: settings.overridesSystemDNS)
            state = .connected
        } catch {
            lastError = error.localizedDescription
            state = .disconnected
        }
        await fetchLogs()
    }

    func disconnect() async {
        guard state == .connected else { return }
        state = .disconnecting
        do {
            try await helper.stop()
        } catch {
            lastError = error.localizedDescription
        }
        state = .disconnected
        await fetchLogs()
    }

    /// Applies changed settings or a changed profile to a live tunnel.
    func reconnect() async {
        guard state == .connected else { return }
        await disconnect()
        await connect()
    }

    func select(_ id: UUID?) async {
        guard store.activeID != id else { return }
        store.activeID = id
        await reconnect()
    }

    func clearLogs() {
        logText = ""
    }

    func dismissError() {
        lastError = nil
    }

    // MARK: - Helper management

    func installHelper() {
        do {
            try helper.register()
        } catch {
            // register() throws while approval is pending; the state check below covers it.
            if helper.installState == .notRegistered { lastError = error.localizedDescription }
        }
        helperState = helper.installState
        if helperState == .requiresApproval { helper.openApprovalSettings() }
    }

    func uninstallHelper() async {
        await disconnect()
        do {
            try await helper.unregister()
        } catch {
            lastError = error.localizedDescription
        }
        helperState = helper.installState
    }

    func openHelperApproval() {
        helper.openApprovalSettings()
    }

    private func ensureHelper() async throws {
        if helper.installState == .notRegistered {
            try? helper.register()
        }
        helperState = helper.installState
        guard helperState == .enabled else {
            helper.openApprovalSettings()
            throw HelperError(
                "Allow ProxyMe in System Settings → General → Login Items & Extensions, then connect again.")
        }
        // A helper left running from an older build must be replaced before use.
        if try await helper.version() != HelperConstants.helperVersion {
            try? await helper.quit()
            try? await Task.sleep(for: .milliseconds(500))
        }
    }

    // MARK: - Polling

    private func poll() async {
        helperState = helper.installState
        guard helperState == .enabled else { return }
        let before = state
        guard before == .connected || before == .disconnected,
              let running = try? await helper.isRunning(),
              state == before else { return }
        if running && before == .disconnected {
            // Tunnel survived an app relaunch.
            state = .connected
        } else if !running && before == .connected {
            state = .disconnected
            lastError = "The proxy core stopped unexpectedly. Check the logs."
        }
        await fetchLogs()
    }

    private func fetchLogs() async {
        guard helperState == .enabled,
              let (data, next) = try? await helper.readLog(from: logOffset) else { return }
        if next < logOffset { logText = "" }
        logOffset = next
        guard !data.isEmpty else { return }
        let chunk = String(decoding: data, as: UTF8.self)
            .replacingOccurrences(of: "\u{1B}\\[[0-9;]*m", with: "", options: .regularExpression)
        logText += chunk
        if logText.count > Self.maxLogLength {
            logText = String(logText.suffix(Self.maxLogLength))
        }
    }
}
