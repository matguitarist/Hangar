import Foundation

/// One setting a runner update changed: "Graphics D3DMetal → Auto".
public struct BottleSettingChange: Sendable, Equatable {
    public var name: String
    public var old: String
    public var new: String

    public init(name: String, old: String, new: String) {
        self.name = name
        self.old = old
        self.new = new
    }
}

/// A bottle whose settings changed under Hangar (S-040): the snapshot it had, and what differs now.
public struct BottleDrift: Sendable, Equatable, Identifiable {
    public var bottle: String
    public var snapshot: SettingsSnapshot
    public var was: BottleSettings
    public var now: BottleSettings
    public var id: String { bottle }
    public var changes: [BottleSettingChange] { BottleSettings.changes(from: was, to: now) }

    public init(bottle: String, snapshot: SettingsSnapshot, was: BottleSettings, now: BottleSettings) {
        self.bottle = bottle
        self.snapshot = snapshot
        self.was = was
        self.now = now
    }
}

extension BottleSettings {
    /// What differs, in the Settings tab's words.
    public static func changes(from old: BottleSettings, to new: BottleSettings) -> [BottleSettingChange] {
        func onOff(_ on: Bool) -> String { on ? String(localized: "On", bundle: .main) : String(localized: "Off", bundle: .main) }
        var list: [BottleSettingChange] = []
        if old.graphics != new.graphics {
            list.append(.init(name: String(localized: "Graphics", bundle: .main), old: old.graphics.title, new: new.graphics.title))
        }
        let toggles: [(String, KeyPath<BottleSettings, Bool>)] = [
            ("MSync", \.msync), (String(localized: "High Resolution Mode", bundle: .main), \.highResolution),
            ("MetalFX", \.metalFX), (String(localized: "AVX for Rosetta", bundle: .main), \.avx),
        ]
        for (name, key) in toggles where old[keyPath: key] != new[keyPath: key] {
            list.append(.init(name: name, old: onOff(old[keyPath: key]), new: onOff(new[keyPath: key])))
        }
        return list
    }
}

extension SnapshotStore {
    /// The bottle's settings as a snapshot kept them, or nil when it kept no bottle files.
    public func bottleSettings(in snapshot: SettingsSnapshot) -> BottleSettings? {
        guard snapshot.files.contains(where: { $0.path == "cxbottle.conf" && $0.existed }) else { return nil }
        return BottleSettings.read(bottle: gameFolder(snapshot.gameID).appending(path: "\(snapshot.id.uuidString)/files"))
    }
}

extension RunnerVersions {
    /// For each bottle, its newest snapshot (from any of its games) compared with the bottle now.
    /// Bottles whose settings are still the snapshot's aren't listed.
    public static func drifts(bottles: [String: [String]], bottleURL: (String) -> URL, store: SnapshotStore) -> [BottleDrift] {
        bottles.keys.sorted().compactMap { bottle in
            let newest = bottles[bottle, default: []].flatMap { store.list($0) }
                .filter { $0.bottle == bottle && store.bottleSettings(in: $0) != nil }
                .max { $0.date < $1.date }
            guard let newest, let was = store.bottleSettings(in: newest) else { return nil }
            let now = BottleSettings.read(bottle: bottleURL(bottle))
            return was == now ? nil : BottleDrift(bottle: bottle, snapshot: newest, was: was, now: now)
        }
    }
}
