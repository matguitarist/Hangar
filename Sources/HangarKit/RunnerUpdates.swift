import Foundation

/// A runner whose version changed since Hangar last looked: "CrossOver 26.3 → 26.4".
public struct RunnerUpdate: Sendable, Equatable, Identifiable {
    public var name: String
    public var path: String
    public var old: String
    public var new: String
    public var id: String { path }
    /// The runner as snapshots name it: "CrossOver 26.3".
    public var oldLabel: String { "\(name) \(old)" }

    public init(name: String, path: String, old: String, new: String) {
        self.name = name
        self.path = path
        self.old = old
        self.new = new
    }
}

/// The runner versions Hangar saw last, kept in a small JSON file: { path: version }.
public enum RunnerVersions {
    public static func load(_ url: URL) -> [String: String] {
        (try? Data(contentsOf: url)).flatMap { try? JSONDecoder().decode([String: String].self, from: $0) } ?? [:]
    }

    public static func save(_ runners: [InstalledRunner], to url: URL) throws {
        var versions: [String: String] = [:]
        for runner in runners { if let version = runner.version { versions[runner.path] = version } }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder.snapshot.encode(versions).write(to: url, options: .atomic)
    }

    /// Runners whose version is not the one seen last. A runner seen for the first time isn't an update.
    public static func changes(previous: [String: String], current: [InstalledRunner]) -> [RunnerUpdate] {
        current.compactMap { runner in
            guard let old = previous[runner.path], let new = runner.version, old != new else { return nil }
            return RunnerUpdate(name: runner.name, path: runner.path, old: old, new: new)
        }
    }

    /// For each game, its newest snapshot marked as working, when that was on the old version.
    public static func lastWorked(on update: RunnerUpdate, gameIDs: [String], store: SnapshotStore) -> [SettingsSnapshot] {
        gameIDs.compactMap { id in
            guard let worked = store.list(id).first(where: { $0.worked != nil }), worked.runner == update.oldLabel else { return nil }
            return worked
        }
    }
}
