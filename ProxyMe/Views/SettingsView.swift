import SwiftUI

struct SettingsView: View {
    @Environment(ProfileStore.self) private var store
    @Environment(TunnelController.self) private var tunnel
    @State private var launchAtLogin = LoginItem.isEnabled

    var body: some View {
        @Bindable var store = store
        Form {
            Section {
                Toggle("Bypass local network (LAN)", isOn: $store.settings.bypassLAN)
                VStack(alignment: .leading, spacing: 6) {
                    Text("Bypass list")
                    TextEditor(text: $store.settings.bypassList)
                        .font(.body.monospaced())
                        .frame(height: 90)
                        .scrollContentBackground(.hidden)
                        .padding(6)
                        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 6))
                    Text("One per line: domains (example.com) or IPs/CIDRs (10.0.0.0/8). These connect directly.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Routing")
            }

            Section("DNS") {
                Picker("Resolver", selection: $store.settings.dns) {
                    ForEach(DNSPreset.allCases) { Text($0.title).tag($0) }
                }
                Toggle("Route system DNS through the tunnel", isOn: $store.settings.overrideSystemDNS)
                    .disabled(store.settings.dns == .system)
                    .help("Prevents DNS leaks to your router/ISP. Restored automatically on disconnect.")
            }

            Section("Local proxy") {
                Toggle("Also expose HTTP + SOCKS5 on 127.0.0.1", isOn: $store.settings.localProxyEnabled)
                TextField("Port", value: $store.settings.localProxyPort, format: .number.grouping(.never))
                    .disabled(!store.settings.localProxyEnabled)
            }

            Section("General") {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in
                        LoginItem.setEnabled(enabled)
                        launchAtLogin = LoginItem.isEnabled
                    }
                Picker("Log level", selection: $store.settings.logLevel) {
                    ForEach(LogLevel.allCases) { Text($0.title).tag($0) }
                }
            }

            Section("Helper") {
                LabeledContent("Privileged helper", value: helperStatus)
                HStack {
                    switch tunnel.helperState {
                    case .notRegistered:
                        Button("Install Helper") { tunnel.installHelper() }
                    case .requiresApproval:
                        Button("Open Login Items Settings") { tunnel.openHelperApproval() }
                    case .enabled:
                        Button("Uninstall Helper", role: .destructive) {
                            Task { await tunnel.uninstallHelper() }
                        }
                    }
                }
                Text("The helper runs as root to create the system-wide tunnel. macOS asks you to allow it once.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if tunnel.state == .connected {
                Section {
                    Button("Apply Changes (Reconnect)") { Task { await tunnel.reconnect() } }
                } footer: {
                    Text("Routing, DNS and local proxy changes take effect on the next connection.")
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Settings")
    }

    private var helperStatus: String {
        switch tunnel.helperState {
        case .notRegistered: "Not installed"
        case .requiresApproval: "Waiting for approval"
        case .enabled: "Installed"
        }
    }
}
