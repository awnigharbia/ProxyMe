import Foundation

@MainActor
final class AppModel {
    static let shared = AppModel()

    let store: ProfileStore
    let tunnel: TunnelController
    let latency = LatencyTester()

    private init() {
        store = ProfileStore()
        tunnel = TunnelController(store: store)
    }
}
