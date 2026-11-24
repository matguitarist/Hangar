import Foundation

/// Pages about a game on the web.
public enum GameLinks {
    static func query(_ text: String) -> String {
        text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed.subtracting(CharacterSet(charactersIn: "&+=?#"))) ?? text
    }

    public static func appleGamingWikiSearch(_ title: String) -> URL {
        URL(string: "https://www.applegamingwiki.com/w/index.php?search=\(query(title))")!
    }
}
