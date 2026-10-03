import Foundation
import Network
import Observation

@MainActor
@Observable
final class LatencyTester {
    enum Result: Equatable {
        case testing, ms(Int), failed, unsupported
    }

    private(set) var results: [UUID: Result] = [:]

    func testAll(_ profiles: [ProxyProfile]) {
        for profile in profiles { test(profile) }
    }

    func test(_ profile: ProxyProfile) {
        guard profile.kind.isTCPReachable else {
            results[profile.id] = .unsupported
            return
        }
        results[profile.id] = .testing
        Task {
            let ms = await Self.tcpHandshake(host: profile.host, port: profile.port)
            results[profile.id] = ms.map(Result.ms) ?? .failed
        }
    }

    /// Milliseconds to complete a TCP handshake, nil on failure/timeout.
    private static func tcpHandshake(host: String, port: Int, timeout: TimeInterval = 5) async -> Int? {
        guard let nwPort = NWEndpoint.Port(rawValue: UInt16(clamping: port)), !host.isEmpty else { return nil }
        let connection = NWConnection(host: NWEndpoint.Host(host), port: nwPort, using: .tcp)
        let queue = DispatchQueue(label: "com.proxyme.latency")
        let started = DispatchTime.now()
        return await withCheckedContinuation { continuation in
            var finished = false  // confined to `queue`
            func finish(_ value: Int?) {
                guard !finished else { return }
                finished = true
                connection.cancel()
                continuation.resume(returning: value)
            }
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    let elapsed = DispatchTime.now().uptimeNanoseconds - started.uptimeNanoseconds
                    finish(Int(elapsed / 1_000_000))
                case .failed, .waiting:
                    finish(nil)
                default:
                    break
                }
            }
            queue.asyncAfter(deadline: .now() + timeout) { finish(nil) }
            connection.start(queue: queue)
        }
    }
}
