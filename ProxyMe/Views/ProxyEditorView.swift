import SwiftUI

struct ProxyEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var draft: ProxyProfile
    private let onSave: (ProxyProfile) -> Void

    init(profile: ProxyProfile, onSave: @escaping (ProxyProfile) -> Void) {
        _draft = State(initialValue: profile)
        self.onSave = onSave
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section("Server") {
                    Picker("Type", selection: kindBinding) {
                        ForEach(ProxyKind.allCases) { Text($0.title).tag($0) }
                    }
                    TextField("Name", text: $draft.name, prompt: Text("Optional"))
                    TextField("Address", text: $draft.host, prompt: Text("proxy.example.com"))
                        .autocorrectionDisabled()
                    TextField("Port", value: $draft.port, format: .number.grouping(.never))
                }

                Section("Authentication") {
                    if draft.kind.usesUsername {
                        TextField(draft.kind == .socks5 || draft.kind == .http || draft.kind == .https
                                  ? "Username" : "User ID",
                                  text: $draft.username, prompt: Text("Optional"))
                            .autocorrectionDisabled()
                    }
                    if draft.kind.usesPassword {
                        SecureField("Password", text: $draft.password)
                    }
                    if draft.kind.usesUUID {
                        TextField("UUID", text: $draft.uuid)
                            .autocorrectionDisabled()
                            .font(.body.monospaced())
                    }
                    if draft.kind == .shadowsocks {
                        Picker("Cipher", selection: $draft.method) {
                            ForEach(ProxyProfile.shadowsocksMethods, id: \.self) { Text($0).tag($0) }
                        }
                    }
                    if draft.kind == .vless {
                        TextField("Flow", text: $draft.flow, prompt: Text("e.g. xtls-rprx-vision"))
                            .autocorrectionDisabled()
                    }
                }

                if draft.kind.supportsTLSOptions {
                    Section("TLS") {
                        if draft.kind.usesUUID {
                            Toggle("Enable TLS", isOn: $draft.tls)
                        }
                        if draft.usesTLS {
                            TextField("Server Name (SNI)", text: $draft.sni, prompt: Text("Defaults to address"))
                                .autocorrectionDisabled()
                            Toggle("Allow insecure certificates", isOn: $draft.allowInsecure)
                            if draft.kind != .hysteria2 {
                                TextField("uTLS Fingerprint", text: $draft.fingerprint, prompt: Text("e.g. chrome"))
                                    .autocorrectionDisabled()
                            }
                            if draft.kind == .vless {
                                TextField("REALITY Public Key", text: $draft.realityPublicKey, prompt: Text("Optional"))
                                    .autocorrectionDisabled()
                                TextField("REALITY Short ID", text: $draft.realityShortID, prompt: Text("Optional"))
                                    .autocorrectionDisabled()
                            }
                        }
                    }
                }

                if draft.kind.supportsTransport {
                    Section("Transport") {
                        Picker("Transport", selection: $draft.transport) {
                            ForEach(TransportKind.allCases) { Text($0.title).tag($0) }
                        }
                        if draft.transport == .ws {
                            TextField("Path", text: $draft.transportPath, prompt: Text("/"))
                                .autocorrectionDisabled()
                            TextField("Host Header", text: $draft.transportHost, prompt: Text("Optional"))
                                .autocorrectionDisabled()
                        } else if draft.transport == .grpc {
                            TextField("Service Name", text: $draft.transportPath)
                                .autocorrectionDisabled()
                        }
                    }
                }

                if !draft.kind.supportsUDP {
                    Section {
                        Label("This proxy type can't carry UDP. QUIC/UDP traffic is blocked so apps fall back to TCP.",
                              systemImage: "info.circle")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .formStyle(.grouped)

            Divider()
            HStack {
                if let problem = draft.validationError {
                    Text(problem).font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save") {
                    onSave(draft)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(draft.validationError != nil)
            }
            .padding(12)
        }
        .frame(width: 520, height: 560)
    }

    /// Switching type moves the port along when it was still the old type's default.
    private var kindBinding: Binding<ProxyKind> {
        Binding(
            get: { draft.kind },
            set: { kind in
                if draft.port == draft.kind.defaultPort { draft.port = kind.defaultPort }
                draft.kind = kind
            })
    }
}
