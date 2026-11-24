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
        _ = find
    }
}
