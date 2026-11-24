import HangarKit
import SwiftUI

/// "Achievements" on a Steam game's page (S-041): how many are unlocked, and the last ones.
struct AchievementsSection: View {
    @Environment(AppModel.self) private var model
    let game: Game

    var body: some View {
        Group {
            if let summary = model.achievements(game.id) {
                Section {
                    VStack(alignment: .leading, spacing: Space.sm) {
                        Text("\(summary.unlocked) of \(summary.total) unlocked")
                        ProgressView(value: summary.fraction)
                            .accessibilityValue(Text("\(summary.unlocked) of \(summary.total) unlocked"))
                    }
                    ForEach(Array(summary.recent.enumerated()), id: \.offset) { _, unlock in
                        LabeledContent(unlock.name, value: unlock.date.formatted(date: .abbreviated, time: .omitted))
                    }
                } header: {
                    Text("Achievements")
                } footer: {
                    Text("From Steam's files on this Mac, updated when Steam runs.").foregroundStyle(.secondary)
                }
            }
        }
    }
}
