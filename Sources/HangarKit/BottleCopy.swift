import Foundation

/// A copy of a bottle for one game, so its settings change that game alone.
public enum BottleCopy {
    /// A folder name for the copy: "Steam – Vernal Edge", then "Steam – Vernal Edge 2"…
    public static func name(for game: String, from bottle: String, in folder: URL) -> String {
        let safe = game.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
        let base = "\(bottle) – \(safe)"
        var name = base
        var n = 2
        while FileManager.default.fileExists(atPath: folder.appending(path: name).path) {
            name = "\(base) \(n)"
            n += 1
        }
        return name
    }

    /// Copies a bottle (APFS clones its files, so even a big bottle copies in moments) and gives
    /// the copy a BottleID of its own. The original isn't changed.
    @concurrent
    public static func copy(_ bottle: URL, to target: URL, id: UUID = UUID()) async throws {
        try FileManager.default.copyItem(at: bottle, to: target)
        let conf = target.appending(path: "cxbottle.conf")
        var file = try ConfFile.read(conf)
        file.set("BottleID", id.uuidString, in: "Bottle")
        try file.write(to: conf)
        // A running wineserver's socket isn't part of a bottle.
        try? FileManager.default.removeItem(at: target.appending(path: ".wineserver"))
    }
}
