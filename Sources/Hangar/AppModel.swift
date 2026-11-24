import Foundation
import HangarKit
import LogKit
import LogKitUI
import Observation

/// The sidebar pages. Snapshot mode walks through every case.
enum SidebarItem: String, CaseIterable, Identifiable, Hashable {
    case overview, log

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview: String(localized: "Overview")
        case .log: String(localized: "Log")
        }
    }

    var symbol: String {
        switch self {
        case .overview: "square.grid.2x2"
        case .log: "doc.text.magnifyingglass"
        }
    }
}

/// What the window shows. Data logic lives in HangarKit.
@Observable
final class AppModel {
    var sidebar: SidebarItem? = .overview
    let log = Store.log
    let logViewer: LogViewerModel

    /// The app's own language. Changing it takes effect after a restart.
    var language: AppLanguage = AppLanguage.current {
        didSet { if language != oldValue { language.apply() } }
    }

    var checksForUpdates: Bool = Updater.shared.automaticallyChecks {
        didSet { if Updater.shared.isAvailable { Updater.shared.automaticallyChecks = checksForUpdates } }
    }

    var settingsTab: SettingsTab = SettingsTab(rawValue: UserDefaults.standard.string(forKey: "settings.tab") ?? "") ?? .general {
        didSet { if !Store.isOverridden { UserDefaults.standard.set(settingsTab.rawValue, forKey: "settings.tab") } }
    }

    init() {
        logViewer = LogViewerModel(store: Store.log)
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        log.post(.info, "Hangar \(version) started", source: "App")
    }
}
