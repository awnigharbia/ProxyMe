import SwiftUI

struct ProxyListView: View {
    @Environment(ProfileStore.self) private var store
    @Environment(TunnelController.self) private var tunnel
    @Environment(LatencyTester.self) private var latency

    @State private var editing: ProxyProfile?
    @State private var importMessage: String?

    var body: some View {
        Group {
            if store.profiles.isEmpty {
                ContentUnavailableView {
                    Label("No Proxies", systemImage: "server.rack")
                } description: {
                    Text("Add a proxy, or copy a share link (socks5://, ss://, vless://, …) and import it.")
                } actions: {
                    Button("Add Proxy") { editing = ProxyProfile() }
                    Button("Import from Clipboard") { importClipboard() }
                }
            } else {
                List {
                    ForEach(store.profiles) { profile in
                        ProxyRow(
                            profile: profile,
                            isActive: profile.id == store.activeID,
                            latency: latency.results[profile.id],
                            onSelect: { Task { await tunnel.select(profile.id) } },
                            onEdit: { editing = profile })
                        .contextMenu {
                            Button("Edit") { editing = profile }
                            Button("Duplicate") { store.duplicate(profile.id) }
                            Button("Test Latency") { latency.test(profile) }
                            Divider()
                            Button("Delete", role: .destructive) { delete(profile) }
                        }
                    }
                    .onMove { store.move(from: $0, to: $1) }
                }
            }
        }
        .navigationTitle("Proxies")
        .toolbar {
            ToolbarItemGroup {
                Button { latency.testAll(store.profiles) } label: {
                    Label("Test Latency", systemImage: "speedometer")
                }
                .disabled(store.profiles.isEmpty)
                .help("TCP handshake time to each server")
                Button { importClipboard() } label: {
                    Label("Import from Clipboard", systemImage: "doc.on.clipboard")
                }
                .help("Import share links from the clipboard")
                Button { editing = ProxyProfile() } label: {
                    Label("Add Proxy", systemImage: "plus")
                }
            }
        }
        .sheet(item: $editing) { profile in
            ProxyEditorView(profile: profile) { saved in
                let wasActive = saved.id == store.activeID
                store.upsert(saved)
                if wasActive { Task { await tunnel.reconnect() } }
            }
        }
        .alert("Import", isPresented: importAlertBinding) {
            Button("OK") {}
        } message: {
            Text(importMessage ?? "")
        }
    }

    private var importAlertBinding: Binding<Bool> {
        Binding(get: { importMessage != nil }, set: { if !$0 { importMessage = nil } })
    }

    private func importClipboard() {
        let text = NSPasteboard.general.string(forType: .string) ?? ""
        let count = store.importURIs(from: text)
        importMessage = count == 0
            ? "No supported proxy links found on the clipboard."
            : "Imported \(count) prox\(count == 1 ? "y" : "ies")."
    }

    private func delete(_ profile: ProxyProfile) {
        let wasActive = profile.id == store.activeID
        Task {
            if wasActive { await tunnel.disconnect() }
            store.delete(profile.id)
        }
    }
}

private struct ProxyRow: View {
    let profile: ProxyProfile
    let isActive: Bool
    let latency: LatencyTester.Result?
    let onSelect: () -> Void
    let onEdit: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onSelect) {
                Image(systemName: isActive ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isActive ? Color.accentColor : .secondary)
            }
            .buttonStyle(.plain)
            .help("Use this proxy")

            VStack(alignment: .leading, spacing: 3) {
                Text(profile.displayName).font(.body.weight(.medium))
                HStack(spacing: 6) {
                    Text(profile.kind.title)
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.quaternary, in: Capsule())
                    Text(profile.endpoint)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer()
            latencyLabel
            Button(action: onEdit) {
                Image(systemName: "pencil")
            }
            .buttonStyle(.borderless)
            .help("Edit")
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture(count: 2, perform: onEdit)
    }

    @ViewBuilder
    private var latencyLabel: some View {
        switch latency {
        case .testing:
            ProgressView().controlSize(.small)
        case .ms(let value):
            Text("\(value) ms")
                .font(.caption.monospacedDigit())
                .foregroundStyle(value < 300 ? .green : (value < 800 ? .orange : .red))
        case .failed:
            Text("Unreachable").font(.caption).foregroundStyle(.red)
        case .unsupported:
            Text("UDP").font(.caption).foregroundStyle(.secondary).help("QUIC-based; TCP test not applicable")
        case nil:
            EmptyView()
        }
    }
}
