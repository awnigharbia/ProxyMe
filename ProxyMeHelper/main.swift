import Foundation

final class HelperService: NSObject, HelperProtocol {
    func version(reply: @escaping (String) -> Void) {
        reply(HelperConstants.helperVersion)
    }

    func start(config: Data, overrideDNS: Bool, reply: @escaping (String?) -> Void) {
        TunnelRunner.shared.start(config: config, overrideDNS: overrideDNS, completion: reply)
    }

    func stop(reply: @escaping () -> Void) {
        TunnelRunner.shared.stop(completion: reply)
    }

    func status(reply: @escaping (Bool) -> Void) {
        TunnelRunner.shared.isRunning(completion: reply)
    }

    func readLog(from offset: UInt64, reply: @escaping (Data, UInt64) -> Void) {
        TunnelRunner.shared.readLog(from: offset, completion: reply)
    }

    func quit(reply: @escaping () -> Void) {
        TunnelRunner.shared.stop {
            reply()
            // Let the reply flush before exiting.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { exit(0) }
        }
    }
}

final class ListenerDelegate: NSObject, NSXPCListenerDelegate {
    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        // Only the ProxyMe app signed by the same team may drive the root helper.
        guard let requirement = CodeSigning.requirement(identifier: HelperConstants.appIdentifier) else {
            return false
        }
        connection.setCodeSigningRequirement(requirement)
        connection.exportedInterface = NSXPCInterface(with: HelperProtocol.self)
        connection.exportedObject = HelperService()
        connection.resume()
        return true
    }
}

// Tear the tunnel down cleanly when launchd stops us (unregister, shutdown).
signal(SIGTERM, SIG_IGN)
let termSource = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
termSource.setEventHandler {
    TunnelRunner.shared.stopSync()
    exit(0)
}
termSource.resume()

TunnelRunner.shared.recover()

let delegate = ListenerDelegate()
let listener = NSXPCListener(machServiceName: HelperConstants.machServiceName)
listener.delegate = delegate
listener.resume()
dispatchMain()
