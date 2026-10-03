import SwiftUI

@main
struct ProxyMeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    private let model = AppModel.shared

    var body: some Scene {
        Window("ProxyMe", id: "main") {
            MainView()
                .environment(model.store)
                .environment(model.tunnel)
                .environment(model.latency)
                .frame(minWidth: 760, minHeight: 480)
        }
        .defaultSize(width: 900, height: 580)

        MenuBarExtra {
            MenuBarContent()
                .environment(model.store)
                .environment(model.tunnel)
        } label: {
            MenuBarLabel(tunnel: model.tunnel)
        }
        .menuBarExtraStyle(.menu)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    /// Quitting must never leave the system routed into a tunnel nobody controls.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let tunnel = AppModel.shared.tunnel
        guard tunnel.state != .disconnected else { return .terminateNow }
        Task { @MainActor in
            await tunnel.disconnect()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}
