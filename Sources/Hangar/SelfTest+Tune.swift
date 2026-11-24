import AppKit
import HangarKit
import SwiftUI

/// M2 (Tune Windows games) and M3 (Recipes) checks, on the sample library.
extension SelfTest {
    /// Plays the sample game Starfall Arcade until it runs, then stops it. Returns the environment and
    /// arguments its script wrote next to itself (macOS doesn't show another process's environment).
    static func launched(_ model: AppModel, _ id: String) async -> (environment: [String: String], arguments: [String]) {
        guard let game = model.game(id) else { return ([:], []) }
        let folder = URL(fileURLWithPath: game.path).appending(path: "Contents/MacOS")
        let envFile = folder.appending(path: "launched-env.txt"), argsFile = folder.appending(path: "launched-args.txt")
        try? FileManager.default.removeItem(at: envFile)
        try? FileManager.default.removeItem(at: argsFile)
        model.play(id)
        for _ in 0..<40 where model.running[id]?.phase != .running || !FileManager.default.fileExists(atPath: argsFile.path) {
            try? await Task.sleep(for: .milliseconds(250))
        }
        model.stop(id)
        for _ in 0..<40 where model.running[id] != nil { try? await Task.sleep(for: .milliseconds(250)) }
        var env: [String: String] = [:]
        for line in ((try? String(contentsOf: envFile, encoding: .utf8)) ?? "").split(separator: "\n") {
            if let eq = line.firstIndex(of: "=") { env[String(line[..<eq])] = String(line[line.index(after: eq)...]) }
        }
        let args = ((try? String(contentsOf: argsFile, encoding: .utf8)) ?? "").split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        return (env, args.last == "" ? Array(args.dropLast()) : args)
    }

    static func tuneChecks(_ model: AppModel) async {
        guard ProcessInfo.processInfo.environment["APP_FIXTURES"] != nil else { return }
        func find(_ title: String) -> Game? { model.library.games.first { $0.title == title } }

        // S-009
        check("S-009 the Runners page lists CrossOver, Wine and Game Porting Toolkit",
              model.runners.map(\.name) == ["CrossOver", "Wine Stable", "Game Porting Toolkit"], model.runners.map(\.name).joined(separator: ","))
        check("S-009 CrossOver shows its version", model.runners.first?.version == "26.3")

        // S-010
        if let vernal = find("Vernal Edge"), var settings = model.bottleSettings(for: vernal) {
            check("S-010 the game page reads the bottle's settings", settings.graphics == .d3dMetal && settings.msync)
            settings.graphics = .dxmt
            settings.avx = true
            settings.highResolution = true
            model.changeBottleSettings(vernal.id, to: settings)
            let reloaded = BottleSettings.read(bottle: model.bottleURL("Steam"))
            check("S-010 changing a setting writes it, and it reads back after a reload", reloaded == settings, String(describing: reloaded))
            let conf = (try? String(contentsOf: BottleSettings.conf(model.bottleURL("Steam")), encoding: .utf8)) ?? ""
            check("S-010 cxbottle.conf holds the new backend", conf.contains("\"CX_GRAPHICS_BACKEND\" = \"dxmt\""))
        } else {
            check("S-010 Vernal Edge has bottle settings", false)
        }

        // S-012: the sample game Starfall Arcade, started with the HUD on.
        if let id = find("Starfall Arcade")?.id {
            model.setOptions(id) { $0.metalHUD = true }
            let env = await launched(model, id).environment
            check("S-012 the HUD setting is kept", model.game(id)?.options.metalHUD == true)
            check("S-012 a launch with the HUD on sets MTL_HUD_ENABLED=1 in the game's process", env["MTL_HUD_ENABLED"] == "1",
                  env["MTL_HUD_ENABLED"] ?? "missing among \(env.count): \(env.keys.sorted().prefix(8).joined(separator: ","))")
            model.setOptions(id) { $0.metalHUD = false }
        }

        // S-013: arguments and a variable reach the sample game.
        if let id = find("Starfall Arcade")?.id {
            model.setOptions(id) {
                $0.arguments = #"-windowed -name "Big Map""#
                $0.variables = [EnvironmentVariable(name: "HANGAR_SELFTEST", value: "a b=c")]
            }
            let seen = await launched(model, id)
            check("S-013 a variable set here reaches the launched process", seen.environment["HANGAR_SELFTEST"] == "a b=c", seen.environment["HANGAR_SELFTEST"] ?? "missing")
            check("S-013 arguments reach the game as typed", seen.arguments == ["-windowed", "-name", "Big Map"], seen.arguments.joined(separator: "|"))
            model.saveNow()
            check("S-013 launch options are saved with the library", LibraryFile.load(from: Store.url).games.first { $0.id == id }?.options.variables.first?.name == "HANGAR_SELFTEST")
            model.setOptions(id) { $0 = GameOptions() }
        }

        // S-011
        if let vernal = find("Vernal Edge") {
            let mates = model.bottleMates(of: vernal).map(\.title)
            check("S-011 the warning names the other games in the bottle", mates.contains("Kynseed") && mates.contains { $0.hasPrefix("Bloodstained") }, mates.joined(separator: ","))
            let originalID = ConfFile(text: (try? String(contentsOf: BottleSettings.conf(model.bottleURL("Steam")), encoding: .utf8)) ?? "").value("BottleID", in: "Bottle")
            let running = model.running
            model.running = [:]
            await model.giveOwnBottle(vernal.id)
            model.running = running
            let moved = find("Vernal Edge")
            check("S-011 Copy makes a new bottle and moves the game to it", moved?.bottle == "Steam – Vernal Edge" && moved?.playtime == vernal.playtime, moved?.bottle ?? "none")
            check("S-011 the other games stay in the original bottle only",
                  model.library.games.filter { $0.title == "Kynseed" }.map(\.bottle) == ["Steam"])
            let copyID = ConfFile(text: (try? String(contentsOf: BottleSettings.conf(model.bottleURL("Steam – Vernal Edge")), encoding: .utf8)) ?? "").value("BottleID", in: "Bottle")
            check("S-011 the copy has its own BottleID", copyID != nil && copyID != originalID)
            check("S-011 the game now has its bottle to itself", moved.map { model.bottleMates(of: $0).isEmpty } == true)
        }
    }
}
