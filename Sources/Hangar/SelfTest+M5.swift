import Foundation
import HangarKit

extension SelfTest {
    /// S-036: the games Heroic installed, in the sample library.
    static func heroicChecks(_ model: AppModel) async {
        guard ProcessInfo.processInfo.environment["APP_FIXTURES"] != nil else { return }
        let heroic = model.games(for: .source(.heroic))
        check("S-036 Heroic's games show under Heroic", heroic.map(\.title) == ["Ember Isles", "Lantern Road", "Paper Kites"], heroic.map(\.title).joined(separator: ","))
        let ember = heroic.first { $0.title == "Ember Isles" }
        check("S-036 with their store on the tile", ember?.sourceLabel == "Heroic · Epic" && ember?.isWindows == true, ember?.sourceLabel ?? "none")
        check("S-036 the DLC isn't a game", !model.library.games.contains { $0.title.hasSuffix("Soundtrack") })
        if let ember {
            let plan = (try? model.launchPlan(for: ember))?.plan
            check("S-036 a Heroic game launches through Heroic", plan?.arguments == ["heroic://launch?appName=Ember&runner=legendary"], plan?.arguments.joined() ?? "none")
            check("S-036 its saves are looked for in Heroic's prefix", model.savePathContext(ember).driveC?.path.hasSuffix("Heroic/Prefixes/Ember/drive_c") == true)
            model.openedURLs = []
            model.openHeroic()
            check("S-036 Open in Heroic opens Heroic", model.openedURLs.first?.lastPathComponent == "Heroic.app")
        }
    }

    /// S-027: the Shortcuts actions, run the way Shortcuts runs them (perform() in Hangar's process).
    static func shortcutsChecks(_ model: AppModel) async {
        guard ProcessInfo.processInfo.environment["APP_FIXTURES"] != nil else { return }
        let query = GameQuery()
        let found = (try? await query.entities(matching: "bg3"))?.map(\.title) ?? []
        check("S-027 a game is found by name with the library's search", found == ["Baldur's Gate 3"], found.joined(separator: ","))
        guard let starfall = try? await query.entities(matching: "starfall").first else {
            return check("S-027 the sample game is found", false)
        }
        let byID = (try? await query.entities(for: [starfall.id]))?.first?.title
        check("S-027 a game is found again by its id", byID == "Starfall Arcade", byID ?? "none")

        _ = try? await PlayGameIntent(game: starfall).perform()
        for _ in 0..<40 where model.running[starfall.id]?.phase != .running { try? await Task.sleep(for: .milliseconds(250)) }
        check("S-027 Play Game launches the sample game", model.running[starfall.id]?.phase == .running)
        let running = (try? await RunningGamesIntent().perform().value) ?? []
        check("S-027 Running Games lists it", running.map(\.id) == [starfall.id], "\(running.map(\.title))")
        _ = try? await StopGameIntent(game: starfall).perform()
        for _ in 0..<40 where model.running[starfall.id] != nil { try? await Task.sleep(for: .milliseconds(250)) }
        check("S-027 Stop Game quits it", model.running[starfall.id] == nil)
        var notRunning = false
        do { _ = try await StopGameIntent(game: starfall).perform() } catch { notRunning = true }
        check("S-027 Stop Game on a game that isn't running says so", notRunning)

        if let knight = model.library.games.first(where: { $0.title == "Hollow Knight" }) {
            let before = model.backupList(knight.id).count
            let saves = model.roots.home.appending(path: "Library/Application Support/unity.Team Cherry.Hollow Knight")
            try? Data("shortcut \(Date())".utf8).write(to: saves.appending(path: "shortcut.dat"))
            _ = try? await BackUpSavesIntent(game: GameEntity(knight)).perform()
            check("S-027 Back Up Saves makes a backup", model.backupList(knight.id).count == before + 1, "\(before) → \(model.backupList(knight.id).count)")
        }
    }
}
