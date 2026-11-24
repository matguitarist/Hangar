import AppKit
import HangarKit
import SwiftUI

/// M2 (Tune Windows games) and M3 (Recipes) checks, on the sample library.
extension SelfTest {
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
