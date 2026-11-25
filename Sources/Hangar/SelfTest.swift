import AppKit
import HangarKit
import SwiftUI

/// Self-test for agents: drives the app model in a test run (APP_STORE in /tmp),
/// prints PASS or FAIL per check, and quits with exit code 0 or 1.
///   APP_STORE=/tmp/Hangar-self.json ~/Applications/Hangar.app/Contents/MacOS/Hangar --selftest
/// (tools/selftest.sh does this.) Add a check for every story with logic.
@MainActor
enum SelfTest {
    static var requested: Bool { CommandLine.arguments.contains("--selftest") }
    /// Read by AppDelegate.applicationWillTerminate.
    static var exitCode: Int32 = 0
    private static var failures = 0
    private static var count = 0

    static func runIfRequested(model: AppModel) {
        guard requested else { return }
        // Print each line at once, so a crash keeps the lines before it.
        setvbuf(stdout, nil, _IOLBF, 0)
        guard Store.isOverridden else {
            print("SELFTEST refused: set APP_STORE to a file in /tmp so the test never touches the real library")
            finish(code: 1)
            return
        }
        Task {
            check("the store is the test file in /tmp", Store.url.path.hasPrefix("/tmp/"), Store.url.path)
            check("the log sits next to the test store", Store.logURL.deletingLastPathComponent() == Store.url.deletingLastPathComponent())
            model.log.post(.info, "Self-test line", source: "SelfTest")
            // LogStore takes a line from any thread and adds it on the main actor.
            for _ in 0..<20 where !model.log.entries.contains(where: { $0.message == "Self-test line" }) {
                try? await Task.sleep(for: .milliseconds(50))
            }
            check("the app writes a log line", model.log.entries.contains { $0.message == "Self-test line" })
            model.log.flushFile()
            let text = (try? String(contentsOf: Store.logURL, encoding: .utf8)) ?? ""
            check("the log line reaches the log file", text.contains("Self-test line"))
            await libraryChecks(model)
            await tuneChecks(model)
            await savesChecks(model)
            await lifeOnAMacChecks(model)
            await shortcutsChecks(model)
            await heroicChecks(model)
            await signInChecks(model)
            await couchChecks(model)
            await controllerChecks(model)
            await achievementChecks(model)
            await m7Checks(model)

            print(failures == 0 ? "SELFTEST PASS \(count) checks" : "SELFTEST FAIL \(failures) of \(count) checks")
            finish(code: failures == 0 ? 0 : 1)
        }
    }

    /// M1: the sample library (APP_FIXTURES) scanned, added to, launched and sorted.
    private static func libraryChecks(_ model: AppModel) async {
        guard ProcessInfo.processInfo.environment["APP_FIXTURES"] != nil else {
            check("APP_FIXTURES names the sample library", false, "run tools/selftest.sh")
            return
        }
        func find(_ title: String) -> Game? { model.library.games.first { $0.title == title } }
        let titles = Set(model.library.games.map(\.title))

        // S-001
        check("S-001 Steam games show with their names", ["Hollow Knight", "Stardew Valley", "Baldur's Gate 3"].allSatisfy(titles.contains))
        check("S-001 Steam's own tools are left out", !titles.contains("Steamworks Common Redistributables"))
        check("S-001 a missing library is noted on the Steam row", model.steamNote?.contains("HangarFixtureDrive") == true, model.steamNote ?? "none")

        // S-002
        let vernal = find("Vernal Edge")
        check("S-002 a bottle's Steam games show", vernal != nil && find("Kynseed") != nil)
        check("S-002 with a CrossOver · Steam badge", vernal?.sourceLabel == "CrossOver · Steam" && vernal?.isWindows == true, vernal?.sourceLabel ?? "")
        check("S-002 programs CrossOver lists show, uninstallers don't", find("Moonlit Harbor") != nil && !titles.contains { $0.hasPrefix("Uninstall") })
        check("S-002 the CrossOver source lists its bottles", model.bottles == ["Classics", "Empty", "Steam"], model.bottles.joined(separator: ","))
        check("S-002 an unreadable bottle says so", model.bottleNote("Empty") != nil)

        // S-003
        check("S-003 Mac apps that are games show", ["Starfall Arcade", "Pocket Racer", "Tiny Tactics"].allSatisfy(titles.contains))
        check("S-003 a non-game app doesn't", !titles.contains("Ledger"))

        // S-004
        let apps = model.roots.appFolders[0]
        model.add(files: [apps.appending(path: "Ledger.app")])
        check("S-004 adding an .app adds and selects it", find("Ledger")?.source == .addedByHand && model.selectedGame?.title == "Ledger")
        let count = model.library.games.count
        model.add(files: [apps.appending(path: "Ledger.app")])
        check("S-004 adding it again makes no duplicate", model.library.games.count == count)
        let exe = model.roots.bottles.appending(path: "Classics/drive_c/Program Files/Moonlit Harbor/MoonlitHarbor.exe")
        model.add(files: [exe])
        check("S-004 an .exe asks for the bottle", model.addRequest?.file == exe && model.addRequest?.isWindowsProgram == true)
        model.addRequest = nil
        model.addWindowsGame(exe, bottle: "Classics")
        let added = find("MoonlitHarbor")
        check("S-004 the .exe joins in its bottle", added?.bottle == "Classics" && added?.exe == "C:/Program Files/Moonlit Harbor/MoonlitHarbor.exe", added?.exe ?? "none")
        check("S-004 a file that isn't a program says so", !AddRequest(file: exe.deletingLastPathComponent().appending(path: "readme.txt")).isWindowsProgram)
        if let id = added?.id {
            model.remove(id)
            check("S-004 a removed game leaves the library", find("MoonlitHarbor") == nil && model.library.removed.contains { $0.id == id })
            await model.refresh()
            check("S-004 a scan doesn't bring it back", find("MoonlitHarbor") == nil)
            model.restore(id)
            check("S-004 Settings brings it back", find("MoonlitHarbor") != nil)
        }

        // S-005
        if let id = find("Tiny Tactics")?.id {
            let image = Store.coversFolder.deletingLastPathComponent().appending(path: "Hangar-self-cover.png")
            if let tiff = NSImage(systemSymbolName: "star", accessibilityDescription: nil)?.tiffRepresentation,
               let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
                try? png.write(to: image)
            }
            model.chooseCover(id, image: image)
            let cover = model.game(id)?.customCover
            check("S-005 Choose Cover keeps a copy of the image", cover.map { FileManager.default.fileExists(atPath: $0) } == true)
            model.resetCover(id)
            check("S-005 Reset Cover goes back", model.game(id)?.customCover == nil)
        }

        // S-030
        model.steamGridDBKey = " test-key "
        check("S-030 the SteamGridDB key is kept (in memory in a test run)", Keychain.read("steamgriddb") == "test-key")
        model.steamGridDBKey = ""
        check("S-030 clearing the key forgets it", Keychain.read("steamgriddb") == nil)

        // S-006: Starfall Arcade (a sample app that runs until stopped) and Pocket Racer (quits at once).
        if let id = find("Starfall Arcade")?.id {
            model.selectedGameID = id
            model.play(id)
            check("S-006 a game shows Starting… or Running at once", model.running[id] != nil)
            for _ in 0..<40 where model.running[id]?.phase != .running { try? await Task.sleep(for: .milliseconds(250)) }
            check("S-006 a native game starts and shows Running", model.running[id]?.phase == .running)
            check("S-006 the Game menu offers Stop", MenuState.shared.isRunning)
            try? await Task.sleep(for: .seconds(3))
            let before = model.game(id)?.playtime ?? 0
            model.stop(id)
            for _ in 0..<40 where model.running[id] != nil { try? await Task.sleep(for: .milliseconds(250)) }
            check("S-006 after it quits, it's no longer running", model.running[id] == nil)
            check("S-006 playtime grows", (model.game(id)?.playtime ?? 0) > before + 2, "\(model.game(id)?.playtime ?? 0)")
            check("S-006 last played is now", model.game(id)?.lastPlayed.map { Date().timeIntervalSince($0) < 30 } == true)
            check("S-006 stopping it isn't 'quit right away'", model.notices[id] == nil)
        }
        if let id = find("Pocket Racer")?.id {
            model.play(id)
            for _ in 0..<60 where model.running[id] != nil { try? await Task.sleep(for: .milliseconds(250)) }
            check("S-006 a game that quits at once says so", model.notices[id] == .quitRightAway, String(describing: model.notices[id]))
        }
        if let id = vernal?.id {
            model.play(id)
            check("S-006 a bottle game without CrossOver says why", model.notices[id] == .didntStart(String(localized: "CrossOver isn't installed.")))
            check("S-006 the bottle's Steam is signed in", model.game(id).map(model.needsSteamSignIn) == false)
            let login = CrossOverScanner.steamFolder(bottle: model.roots.bottles.appending(path: "Steam")).appending(path: "config/loginusers.vdf")
            try? FileManager.default.removeItem(at: login)
            await model.refresh()
            check("S-006 a signed-out bottle Steam asks to sign in", model.game(id).map(model.needsSteamSignIn) == true)
        }

        // S-008
        model.searchText = "bg3"
        check("S-008 bg3 finds Baldur's Gate 3", model.games(for: .allGames).map(\.title) == ["Baldur's Gate 3"])
        model.searchText = "knight hollow"
        check("S-008 knight hollow finds Hollow Knight", model.games(for: .allGames).map(\.title) == ["Hollow Knight"])
        model.searchText = ""
        model.newCollection()
        guard let first = model.library.collections.last, let knight = find("Hollow Knight")?.id else {
            return check("S-008 a new collection shows", false)
        }
        model.renameCollection(first.id, to: "Favorites")
        model.newCollection()
        let second = model.library.collections.last?.id ?? first.id
        check("S-008 a new collection shows in the sidebar", model.library.collections.count == 2 && model.sidebar == .collection(second))
        model.addToCollection([knight], first.id)
        model.addToCollection([knight], second)
        check("S-008 a game can be in several collections", model.games(for: .collection(first.id)).map(\.id) == [knight]
              && model.games(for: .collection(second)).map(\.id) == [knight])
        model.sort = .playtime
        check("S-008 sorting by playtime puts the most played first", model.games(for: .allGames).first?.title == "Starfall Arcade")
        model.sort = .name
        await model.saveNow()
        check("S-008 collections are saved", Store.savedLibrary.collections.map(\.name).contains("Favorites"))
    }

    static func check(_ name: String, _ ok: Bool, _ detail: String = "") {
        count += 1
        if !ok { failures += 1 }
        print(ok ? "PASS \(name)" : "FAIL \(name)\(detail.isEmpty ? "" : ": \(detail)")")
    }

    /// Quits through NSApp.terminate, never exit(), and closes sheets first:
    /// an open sheet refuses terminate, and the run would wait forever.
    static func finish(code: Int32) {
        exitCode = code
        for window in NSApp.windows { if let sheet = window.attachedSheet { window.endSheet(sheet) } }
        NSApp.terminate(nil)
    }
}
