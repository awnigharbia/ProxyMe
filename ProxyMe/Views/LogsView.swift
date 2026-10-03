import SwiftUI

struct LogsView: View {
    @Environment(TunnelController.self) private var tunnel
    private static let bottomID = "bottom"

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                Text(tunnel.logText.isEmpty ? "No log output yet. Connect to see activity." : tunnel.logText)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(tunnel.logText.isEmpty ? .secondary : .primary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                Color.clear.frame(height: 1).id(Self.bottomID)
            }
            .onChange(of: tunnel.logText) {
                proxy.scrollTo(Self.bottomID, anchor: .bottom)
            }
            .onAppear { proxy.scrollTo(Self.bottomID, anchor: .bottom) }
        }
        .navigationTitle("Logs")
        .toolbar {
            ToolbarItemGroup {
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(tunnel.logText, forType: .string)
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                }
                .disabled(tunnel.logText.isEmpty)
                Button { tunnel.clearLogs() } label: {
                    Label("Clear", systemImage: "trash")
                }
                .disabled(tunnel.logText.isEmpty)
            }
        }
    }
}
