import Foundation
import Observation

@MainActor
@Observable
final class ProfileStore {
    private struct Snapshot: Codable {
        var profiles: [ProxyProfile] = []
        var activeID: UUID?
        var settings = AppSettings()
    }

    private var snapshot = Snapshot()
    private let fileURL: URL

    var profiles: [ProxyProfile] { snapshot.profiles }

    var activeID: UUID? {
        get { snapshot.activeID }
        set { snapshot.activeID = newValue; save() }
    }

    var settings: AppSettings {
        get { snapshot.settings }
        set { snapshot.settings = newValue; save() }
    }

    var activeProfile: ProxyProfile? {
        profiles.first { $0.id == activeID }
    }

    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("ProxyMe", isDirectory: true)
        try? FileManager.default.createDirectory(
            at: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        fileURL = dir.appendingPathComponent("state.json")
        if let data = try? Data(contentsOf: fileURL),
           let saved = try? JSONDecoder().decode(Snapshot.self, from: data) {
            snapshot = saved
        }
    }

    /// Inserts or replaces by id; the first profile becomes active automatically.
    func upsert(_ profile: ProxyProfile) {
        if let index = snapshot.profiles.firstIndex(where: { $0.id == profile.id }) {
            snapshot.profiles[index] = profile
        } else {
            snapshot.profiles.append(profile)
        }
        if snapshot.activeID == nil { snapshot.activeID = profile.id }
        save()
    }

    func delete(_ id: UUID) {
        snapshot.profiles.removeAll { $0.id == id }
        if snapshot.activeID == id { snapshot.activeID = snapshot.profiles.first?.id }
        save()
    }

    func duplicate(_ id: UUID) {
        guard var copy = profiles.first(where: { $0.id == id }) else { return }
        copy.id = UUID()
        copy.name = copy.displayName + " copy"
        snapshot.profiles.append(copy)
        save()
    }

    func move(from source: IndexSet, to destination: Int) {
        snapshot.profiles.move(fromOffsets: source, toOffset: destination)
        save()
    }

    /// Imports every proxy URI found in `text`; returns how many were added.
    @discardableResult
    func importURIs(from text: String) -> Int {
        let parsed = URIParser.parseAll(text)
        for profile in parsed { upsert(profile) }
        return parsed.count
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        // Credentials live here, so keep the file owner-only.
        try? data.write(to: fileURL, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
    }
}
