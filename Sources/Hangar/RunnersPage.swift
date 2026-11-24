import AppKit
import HangarKit
import SwiftUI

/// What runs Windows games on this Mac: CrossOver and its bottles, Wine builds, Game Porting Toolkit, MacRunner.
struct RunnersPage: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Form {
            Section {
                PageHeader(symbol: "gearshape.2", title: String(localized: "Runners"),
                           summary: String(localized: "What runs your Windows games. Hangar finds them in the Applications folders and Homebrew.")) {
                    Button("Refresh") { Task { await model.refresh() } }
                }
            }
            crossOver
            let others = model.runners.filter { $0.kind != .crossOver }
            Section("Wine and Game Porting Toolkit") {
                if others.isEmpty {
                    Text("None installed. A Wine build or Game Porting Toolkit runs a game in a prefix of its own.")
                        .foregroundStyle(.secondary)
                    Link("Get Wine builds for the Mac", destination: URL(string: "https://github.com/Gcenx/macOS_Wine_builds")!)
                } else {
                    ForEach(others) { runner in RunnerRow(runner: runner) }
                }
            }
        }
        .formStyle(.grouped)
        .gridArea("runners", inset: 0)
        .navigationTitle("Runners")
    }

    @ViewBuilder
    private var crossOver: some View {
        Section("CrossOver") {
            if let runner = model.runners.first(where: { $0.kind == .crossOver }) {
                RunnerRow(runner: runner)
                LabeledContent("Bottles") {
                    Text(model.bottles.isEmpty ? String(localized: "None") : model.bottles.joined(separator: ", "))
                        .multilineTextAlignment(.trailing)
                }
            } else {
                Text("CrossOver isn't installed. Hangar needs it to play the Windows games in your bottles.")
                    .foregroundStyle(.secondary)
                Link("Get CrossOver", destination: URL(string: "https://www.codeweavers.com/crossover")!)
            }
        }
    }
}

/// One runner: its name, version and place, with Show in Finder.
private struct RunnerRow: View {
    let runner: InstalledRunner

    var body: some View {
        LabeledContent {
            HStack(spacing: Space.sm) {
                Text(runner.version.map { String(localized: "Version \($0)") } ?? String(localized: "Version unknown"))
                    .foregroundStyle(.secondary)
                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: runner.path)])
                } label: {
                    Label("Show in Finder", systemImage: "folder")
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .help(String(localized: "Show \(runner.name) in the Finder"))
            }
        } label: {
            Text(runner.name)
            Text(runner.path)
                .lineLimit(1)
                .truncationMode(.middle)
                .help(runner.path)
        }
    }
}
