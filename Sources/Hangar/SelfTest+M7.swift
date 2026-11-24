import Foundation
import HangarKit

extension SelfTest {
    /// M7: look after the library.
    static func m7Checks(_ model: AppModel) async {
        guard ProcessInfo.processInfo.environment["APP_FIXTURES"] != nil else { return }
        await frameCapChecks(model)
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
