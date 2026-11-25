import AppKit
import SwiftUI

/// The Settings window (Command-Comma). One tab per topic, at most about
/// six. Each tab is a grouped Form that sizes to its content, so the
/// window grows to fit and shows no scroll bar it does not need.
struct SettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        TabView(selection: $model.settingsTab) {
            ForEach(SettingsTab.allCases) { tab in
                page(tab)
                    .tabItem { Label(tab.title, systemImage: tab.symbol) }
                    .tag(tab)
            }
        }
        .noInitialFocus()
    }

    @ViewBuilder
    private func page(_ tab: SettingsTab) -> some View {
        Form {
            switch tab {
            case .general: GeneralSettings()
            case .library: LibrarySettings()
            case .appearance: AppearanceSettings()
            case .updates: UpdateSettings()
            }
        }
        .formStyle(.grouped)
        .fitsContent()
        .frame(width: 520)
    }
}

/// The Settings tabs. Snapshot mode walks through every case.
enum SettingsTab: String, CaseIterable, Identifiable {
    case general, library, appearance, updates

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: String(localized: "General")
        case .library: String(localized: "Library")
        case .appearance: String(localized: "Appearance")
        case .updates: String(localized: "Updates")
        }
    }

    var symbol: String {
        switch self {
        case .general: "gearshape"
        case .library: "books.vertical"
        case .appearance: "paintpalette"
        case .updates: "arrow.triangle.2.circlepath"
        }
    }
}

struct GeneralSettings: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Section("Language") {
            Picker("Language", selection: $model.language) {
                Text("System (\(AppLanguage.systemName))").tag(AppLanguage.system)
                // Every language the app is translated into, each named in itself.
                ForEach(AppLanguage.available, id: \.self) { language in
                    Text(verbatim: language.name).tag(language)
                }
            }
            if model.language != AppLanguage.atLaunch {
                HStack {
                    Text("The new language applies after a restart.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Restart Now") { AppLanguage.relaunch() }
                }
            }
        }
        Section {
            Toggle("Show Hangar in the menu bar", isOn: $model.showsInMenuBar)
        } header: {
            Text("Menu Bar")
        } footer: {
            Text("Play a recent game or see what's running from the menu bar. Hangar keeps running when you close its window.")
                .foregroundStyle(.secondary)
        }
    }
}

/// Settings > Library: where Steam is, and the games taken out of the library.
struct LibrarySettings: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Section("Steam") {
            LabeledContent("Steam Folder") {
                HStack {
                    Text(model.roots.steam.path)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .help(model.roots.steam.path)
                        .foregroundStyle(.secondary)
                    Button("Choose…") { GamePanels.chooseSteamFolder(model) }
                }
            }
        }
        Section {
            SecureField("SteamGridDB API Key", text: $model.steamGridDBKey, prompt: Text("Optional"))
            Link("Get a free key on steamgriddb.com", destination: URL(string: "https://www.steamgriddb.com/profile/preferences/api")!)
        } header: {
            Text("Cover Art")
        } footer: {
            Text("Steam games get their covers from the Steam store. With a SteamGridDB key, Hangar also finds covers the store doesn't have, and covers for Windows games that aren't on Steam. Sign in with Steam on steamgriddb.com, then make a key under Preferences › API.")
                .foregroundStyle(.secondary)
        }
        Section {
            SecureField("TheGamesDB API Key", text: $model.theGamesDBKey, prompt: Text("Optional"))
            Link("Request a key on the TheGamesDB forums", destination: URL(string: "https://forums.thegamesdb.net/viewforum.php?f=10")!)
        } header: {
            Text("Game Details")
        } footer: {
            Text("Steam games get their description, developer and genres from the Steam store. With a TheGamesDB key, Hangar also finds them for games that aren't on Steam.")
                .foregroundStyle(.secondary)
        }
        Section {
            Toggle("Keep save backups in iCloud Drive", isOn: $model.backupsInICloud)
        } header: {
            Text("Save Backups")
        } footer: {
            Text("Hangar copies a game's saves each time you play it and keeps the last ten copies. In iCloud Drive, they're also on your other Macs.")
                .foregroundStyle(.secondary)
        }
        Section {
            LabeledContent("Library File") {
                HStack {
                    Button("Export Library…") { GamePanels.exportLibrary(model) }
                    Button("Import Library…") { GamePanels.importLibrary(model) }
                }
            }
        } footer: {
            Text("Playtime, collections, the covers you chose and game settings, for another Mac or after a reinstall.")
                .foregroundStyle(.secondary)
        }
        Section {
            if model.library.removed.isEmpty {
                Text("No removed games.").foregroundStyle(.secondary)
            }
            ForEach(model.library.removed) { game in
                LabeledContent(game.title) {
                    Button("Restore") { model.restore(game.id) }
                }
            }
        } header: {
            Text("Removed Games")
        } footer: {
            Text("Games you remove stay on disk. Restore one to see it in the library again.")
                .foregroundStyle(.secondary)
        }
    }
}

/// Settings > Updates: Sparkle's automatic checks.
struct UpdateSettings: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Section("Automatic Updates") {
            Toggle(isOn: $model.checksForUpdates) {
                Text("Check for updates automatically")
                Text(updatesNote)
            }
            .disabled(!Updater.shared.isAvailable)
            LabeledContent("Version \(Self.version)") {
                Button("Check Now") { Updater.shared.checkForUpdates() }
                    .disabled(!Updater.shared.isAvailable)
            }
        }
    }

    static var version: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?" }

    private var updatesNote: String {
        guard Updater.shared.isAvailable else { return String(localized: "Updates are off in this build.") }
        guard let last = Updater.shared.lastCheck else { return String(localized: "Looks once a day for a new version on GitHub.") }
        return String(localized: "Looks once a day for a new version on GitHub. Last checked \(last.formatted(.relative(presentation: .named))).")
    }
}
