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

        // S-014: Moonlit Harbor picks the sample Wine build.
        if let harbor = find("Moonlit Harbor"), let wine = model.runners.first(where: { $0.kind == .wine }) {
            model.setOptions(harbor.id) { $0.runner = wine.path }
            let game = model.game(harbor.id)!
            let plan = try? LaunchPlanner.plan(for: game, roots: model.roots)
            check("S-014 a game can run through a Wine build", plan?.executable.path == wine.wine && model.runnerLabel(game) == "Wine Stable")
            check("S-014 in a prefix of its own", plan?.environment["WINEPREFIX"]?.hasPrefix(model.roots.prefixes.path) == true)
            model.setOptions(harbor.id) { $0.runner = nil }
        }

        // S-015: the sample pages in Tests/Fixtures/AppleGamingWiki.
        if let knight = find("Hollow Knight"), let pocket = find("Pocket Racer") {
            await model.loadCompatibility(knight.id)
            let entries = model.compatibility[knight.id]??.entries ?? []
            check("S-015 a game page shows the verdict for each method", entries.map(\.method) == [.native, .rosetta, .crossOver, .wine, .parallels]
                  && entries.first?.rating == .perfect, entries.map(\.method.rawValue).joined(separator: ","))
            check("S-015 the verdicts are cached for offline use",
                  FileManager.default.fileExists(atPath: Store.compatibilityFolder.appending(path: "Hollow_Knight.json").path))
            await model.loadCompatibility(pocket.id)
            check("S-015 a game without a wiki page says so", model.compatibility[pocket.id] == .some(nil))
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

        // S-017: change, break, restore, on Kynseed in the bottle Steam.
        if let kynseed = find("Kynseed"), var good = model.bottleSettings(for: kynseed) {
            good.graphics = .dxvk
            model.changeBottleSettings(kynseed.id, to: good)
            let before = model.snapshotList(kynseed.id).count
            var broken = good
            broken.graphics = .wined3d
            broken.msync = false
            model.changeBottleSettings(kynseed.id, to: broken)
            let list = model.snapshotList(kynseed.id)
            check("S-017 a snapshot is saved before every change", list.count == before + 1 && list.first?.reason == .settings, "\(before) → \(list.count)")
            if let snapshot = list.first {
                model.restore(snapshot)
                check("S-017 change, break, restore: the settings come back", model.bottleSettings(for: kynseed) == good,
                      String(describing: model.bottleSettings(for: kynseed)))
                check("S-017 restoring saves the broken settings first", model.snapshotList(kynseed.id).first?.reason == .restore)
            }
        }
        if let starfall = find("Starfall Arcade") {
            model.play(starfall.id)
            let launch = model.launchSnapshots[starfall.id]
            for _ in 0..<40 where model.running[starfall.id]?.phase != .running { try? await Task.sleep(for: .milliseconds(250)) }
            model.stop(starfall.id)
            for _ in 0..<40 where model.running[starfall.id] != nil { try? await Task.sleep(for: .milliseconds(250)) }
            check("S-017 a snapshot is taken when a game starts", launch?.reason == .launch || launch != nil)
            model.notices[starfall.id] = .askWorked
            model.markWorked(starfall.id)
            let labeled = model.snapshotList(starfall.id).first { $0.id == launch?.id }
            check("S-017 marking a launch \"worked\" labels that snapshot", labeled?.worked != nil && model.notices[starfall.id] == nil)        }
    }
}
