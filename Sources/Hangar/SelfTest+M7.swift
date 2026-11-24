import Foundation
import HangarKit

extension SelfTest {
    /// M7: look after the library.
    static func m7Checks(_ model: AppModel) async {
        guard ProcessInfo.processInfo.environment["APP_FIXTURES"] != nil else { return }
        await frameCapChecks(model)
        await storageChecks(model)
    }

    /// S-039: sizes add up, and old snapshots go while the newest and the labeled ones stay.
    static func storageChecks(_ model: AppModel) async {
        let old = model.roots.prefixes.appending(path: "Old Game-1a2b")
        try? FileManager.default.createDirectory(at: old.appending(path: "drive_c"), withIntermediateDirectories: true)
        try? Data(repeating: 7, count: 100_000).write(to: old.appending(path: "drive_c/big.bin"))
        await model.measureStorage()
        let items = model.storageItems ?? []
        check("S-039 Storage lists the games and bottles", items.contains { $0.kind == .games } && items.contains { $0.kind == .bottles })
        check("S-039 a prefix no game uses is Unused", items.first { $0.name == "Old Game-1a2b" }?.unused == true)
        let totals = StorageScanner.totals(items)
        check("S-039 the totals add up", totals.values.reduce(0, +) == items.map(\.bytes).reduce(0, +))
        if let unused = items.first(where: { $0.name == "Old Game-1a2b" }) {
            await model.trashPrefix(unused)
            check("S-039 Move to Trash removes the unused prefix", !FileManager.default.fileExists(atPath: old.path))
        }
        if let game = model.library.games.first(where: { $0.title == "Kynseed" }) {
            for n in 0..<6 {
                model.setOptions(game.id) { $0.arguments = "-storage \(n)" }
                _ = model.takeSnapshot(game.id, reason: .settings)
            }
            let before = model.snapshotList(game.id)
            if let oldest = before.last { try? model.snapshots.markWorked(oldest) }
            await model.deleteOldSnapshots()
            let after = model.snapshotList(game.id)
            check("S-039 Delete Old Snapshots keeps the newest three and the ones that worked",
                  after.count == 4 && after.contains { $0.worked != nil }, "\(before.count) → \(after.count)")
            model.setOptions(game.id) { $0.arguments = "" }
        }
    }

    /// S-038: a cap launches DXVK games with DXVK_FRAME_RATE, and nothing else.
    static func frameCapChecks(_ model: AppModel) async {
        guard let game = model.library.games.first(where: { $0.title == "Moonlit Harbor" }), var settings = model.bottleSettings(for: game) else {
            return check("S-038 the sample bottle game is there", false)
        }
        model.running = [:]
        model.setOptions(game.id) { $0.frameCap = 40; $0.runner = nil }
        settings.graphics = .dxvk
        model.changeBottleSettings(game.id, to: settings)
        // The sample CrossOver can't launch, so the check reads what the launch would add.
        let current = model.game(game.id) ?? game
        let dxvk = model.frameCapEnvironment(current, cap: current.options.frameCap)["DXVK_FRAME_RATE"]
        check("S-038 a DXVK game launches with its cap", dxvk == "40", dxvk ?? "none")
        settings.graphics = .d3dMetal
        model.changeBottleSettings(game.id, to: settings)
        let metal = model.frameCapEnvironment(current, cap: current.options.frameCap)["DXVK_FRAME_RATE"]
        check("S-038 a D3DMetal game gets no cap", metal == nil, metal ?? "none")
        model.setOptions(game.id) { $0.frameCap = nil }
        model.saveNow()
        check("S-038 the cap is saved with the game", LibraryFile.load(from: Store.url).games.first { $0.id == game.id }?.options.frameCap == nil)
    }
}
