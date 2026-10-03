import SwiftUI

struct MenuBarLabel: View {
    let tunnel: TunnelController

    var body: some View {
        Image(systemName: tunnel.state == .connected ? "shield.lefthalf.filled" : "shield")
    }
}

struct MenuBarContent: View {
    @Environment(ProfileStore.self) private var store
    @Environment(TunnelController.self) private var tunnel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Text(statusLine)
        Button(tunnel.state == .connected ? "Disconnect" : "Connect") {
            Task { await tunnel.toggle() }
        }
        .disabled(tunnel.isBusy || store.activeProfile == nil)

        if !store.profiles.isEmpty {
            Divider()
            Picker("Proxy", selection: activeBinding) {
                ForEach(store.profiles) { profile in
                    Text(profile.displayName).tag(Optional(profile.id))
                }
            }
            .pickerStyle(.inline)
        }

        Divider()
        Button("Open ProxyMe") {
            openWindow(id: "main")
            NSApp.activate(ignoringOtherApps: true)
        }
        Button("Quit ProxyMe") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }

    private var statusLine: String {
        guard tunnel.state == .connected, let name = store.activeProfile?.displayName else {
            return tunnel.statusText
        }
        return "Connected — \(name)"
    }

    private var activeBinding: Binding<UUID?> {
        Binding(
            get: { store.activeID },
            set: { id in Task { await tunnel.select(id) } })
    }
}
