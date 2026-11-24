import Foundation
import HangarKit

/// Fetching all the library's details at once (S-032), with its progress for the banner.
struct DetailsRun: Equatable {
    var total: Int
    var done = 0
    var found = 0
    var finished = false
    var stopped = false
}

/// What games are about (S-031), one at a time or the whole library (S-032).
extension AppModel {
    /// Reads what a game is about: the Steam store in the app's language, else TheGamesDB by title.
    /// `force` asks again however fresh the cache is (Refresh Details).
    @discardableResult
    func loadDetails(_ id: String, force: Bool = false) async -> GameDetails? {
        if !force, let known = details[id] { return known }
        guard let game = game(id) else { return nil }
        let result: GameDetails?
        if let steamID = game.steamID {
            let language = SteamDetails.language(for: Bundle.main.preferredLocalizations.first ?? "en")
            result = await detailsCache.details(steamID: steamID, language: language, force: force)
        } else {
            result = await detailsCache.details(title: game.title, mac: !game.isWindows, force: force)
        }
        details[id] = .some(result)
        return result
    }

    /// Game › Refresh Details: asks the Steam store or TheGamesDB again for one game.
    func refreshDetails(_ id: String) {
        Task {
            let found = await loadDetails(id, force: true)
            log.post(found == nil ? .warning : .info, "\(found == nil ? "No details found" : "Refreshed the details") for \(game(id)?.title ?? id)", source: "Details")
        }
    }

    /// View › Fetch All Details: every game in the library, one after another. Details already
    /// fetched this month come from the cache at once; the Steam store is asked at its own pace.
    func fetchAllDetails() {
        guard detailsTask == nil else { return }
        let ids = library.games.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }.map(\.id)
        detailsRun = DetailsRun(total: ids.count)
        log.post(.info, "Fetching the details of \(ids.count) games", source: "Details")
        detailsTask = Task {
            for id in ids {
                if Task.isCancelled { break }
                if await loadDetails(id) != nil { detailsRun?.found += 1 }
                detailsRun?.done += 1
            }
            detailsRun?.finished = true
            detailsRun?.stopped = Task.isCancelled
            if let run = detailsRun {
                log.post(.info, "Found details for \(run.found) of \(run.total) games\(run.stopped ? " (stopped)" : "")", source: "Details")
            }
            detailsTask = nil
            syncMenu()
        }
        syncMenu()
    }

    func stopFetchingDetails() {
        detailsTask?.cancel()
    }
}
