import AppKit
import LogKitUI
import SwiftUI

struct ContentView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openSettings) private var openSettings
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            page(model.sidebar ?? .overview)
        }
        .task {
            SeedData.addIfRequested(model: model)
            SelfTest.runIfRequested(model: model)
            Snapshot.runIfRequested(model: model, openSettings: openSettings, openWindow: openWindow)
        }
    }

    private var sidebar: some View {
        @Bindable var model = model
        return List(selection: $model.sidebar) {
            ForEach(SidebarItem.allCases) { item in
                Label(item.title, systemImage: item.symbol)
                    .tag(item)
            }
        }
        .navigationSplitViewColumnWidth(min: 200, ideal: 220)
    }

    @ViewBuilder
    private func page(_ item: SidebarItem) -> some View {
        switch item {
        case .overview:
            ContentUnavailableView {
                Label("Hangar", systemImage: "gamecontroller")
            } description: {
                Text("Every game on this Mac in one library: Mac games, and Windows games that run through CrossOver and other runners. Hangar finds them, launches them, and keeps their settings and saves safe.")
            }
            .navigationTitle("Overview")
        case .log:
            LogViewer(model: model.logViewer, options: LogViewerOptions(
                emptyTitle: String(localized: "No Log Lines Yet"),
                emptyMessage: String(localized: "What Hangar does, such as finding and launching games, is written here.")))
                .navigationTitle("Log")
        }
    }
}

/// Seed mode for snapshots: a few log lines so the Log page has something to show.
enum SeedData {
    static func addIfRequested(model: AppModel) {
        guard ProcessInfo.processInfo.environment["APP_SEED"] == "1", Store.isOverridden else { return }
        model.log.post(.info, "Found 5 games in the Steam library", source: "Library")
        model.log.post(.debug, "Read libraryfolders.vdf", source: "Library")
        model.log.post(.warning, "The Steam library on Data isn't connected", source: "Library")
        model.log.post(.info, "Started Vernal Edge in the bottle Steam", source: "Launch")
        model.log.post(.error, "Kynseed quit after 4 seconds", source: "Launch")
    }
}
