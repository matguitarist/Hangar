import Foundation

/// A page about a game on the web.
public struct GameLink: Sendable, Equatable, Identifiable {
    public enum Site: String, Sendable, CaseIterable {
        case appleGamingWiki, pcGamingWiki, codeWeavers, protonDB, steam

        /// Site names are proper names: the same in every language.
        public var name: String {
            switch self {
            case .appleGamingWiki: "AppleGamingWiki"
            case .pcGamingWiki: "PCGamingWiki"
            case .codeWeavers: "CodeWeavers"
            case .protonDB: "ProtonDB"
            case .steam: "Steam"
            }
        }
    }

    public var site: Site
    public var url: URL
    /// True when the link searches by title instead of opening the game's own page.
    public var isSearch: Bool
    public var id: Site { site }
}

/// Pages about a game on the web, from its store id when it has one, or its title.
public enum GameLinks {
    static func query(_ text: String) -> String {
        text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed.subtracting(CharacterSet(charactersIn: "&+=?#"))) ?? text
    }

    public static func appleGamingWikiSearch(_ title: String) -> URL {
        URL(string: "https://www.applegamingwiki.com/w/index.php?search=\(query(title))")!
    }

    public static func store(steamID: String?) -> URL? {
        steamID.flatMap { id in id.allSatisfy(\.isNumber) ? URL(string: "https://store.steampowered.com/app/\(id)/") : nil }
    }

    /// Every page for a game. `wikiPage` is its AppleGamingWiki page when Hangar found one.
    public static func links(title: String, steamID: String?, wikiPage: String? = nil) -> [GameLink] {
        let steam = steamID.flatMap { $0.allSatisfy(\.isNumber) && !$0.isEmpty ? $0 : nil }
        let q = query(title)
        var links: [GameLink] = [
            wikiPage.map { GameLink(site: .appleGamingWiki, url: AppleGamingWiki.pageURL($0), isSearch: false) }
                ?? GameLink(site: .appleGamingWiki, url: appleGamingWikiSearch(title), isSearch: true),
            steam.map { GameLink(site: .pcGamingWiki, url: URL(string: "https://www.pcgamingwiki.com/api/appid.php?appid=\($0)")!, isSearch: false) }
                ?? GameLink(site: .pcGamingWiki, url: URL(string: "https://www.pcgamingwiki.com/w/index.php?search=\(q)")!, isSearch: true),
            GameLink(site: .codeWeavers, url: URL(string: "https://www.codeweavers.com/compatibility?name=\(q)")!, isSearch: true),
            steam.map { GameLink(site: .protonDB, url: URL(string: "https://www.protondb.com/app/\($0)")!, isSearch: false) }
                ?? GameLink(site: .protonDB, url: URL(string: "https://www.protondb.com/search?q=\(q)")!, isSearch: true),
        ]
        if let store = store(steamID: steam) { links.append(GameLink(site: .steam, url: store, isSearch: false)) }
        return links
    }
}
