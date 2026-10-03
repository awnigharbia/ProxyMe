import SwiftUI

struct MainView: View {
    private enum Pane: String, CaseIterable, Identifiable {
        case proxies, settings, logs

        var id: String { rawValue }
        var title: String { rawValue.capitalized }
        var icon: String {
            switch self {
            case .proxies: "server.rack"
            case .settings: "gearshape"
            case .logs: "text.alignleft"
            }
        }
    }

    @State private var pane: Pane? = .proxies

    var body: some View {
        NavigationSplitView {
            List(Pane.allCases, selection: $pane) { pane in
                Label(pane.title, systemImage: pane.icon).tag(pane)
            }
            .safeAreaInset(edge: .bottom) { ConnectionPanel() }
            .navigationSplitViewColumnWidth(min: 210, ideal: 230, max: 280)
        } detail: {
            switch pane ?? .proxies {
            case .proxies: ProxyListView()
            case .settings: SettingsView()
            case .logs: LogsView()
            }
        }
    }
}

struct ConnectionPanel: View {
    @Environment(ProfileStore.self) private var store
    @Environment(TunnelController.self) private var tunnel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Circle().fill(statusColor).frame(width: 9, height: 9)
                Text(tunnel.statusText).font(.headline)
                if tunnel.isBusy { ProgressView().controlSize(.small) }
            }
            Text(store.activeProfile?.displayName ?? "No proxy selected")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            if let error = tunnel.lastError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .lineLimit(6)
            }

            Button {
                Task { await tunnel.toggle() }
            } label: {
                Text(tunnel.state == .connected ? "Disconnect" : "Connect")
                    .frame(maxWidth: .infinity)
            }
            .controlSize(.large)
            .buttonStyle(.borderedProminent)
            .tint(tunnel.state == .connected ? .red : .accentColor)
            .disabled(tunnel.isBusy || store.activeProfile == nil)
        }
        .padding(12)
        .background(.bar)
    }

    private var statusColor: Color {
        switch tunnel.state {
        case .connected: .green
        case .disconnected: .secondary
        default: .orange
        }
    }
}
