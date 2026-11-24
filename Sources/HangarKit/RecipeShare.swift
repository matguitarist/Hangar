import Foundation

/// A game's working setup as a recipe to send to Hangar's recipe list.
public enum RecipeShare {
    /// Hangar's GitHub repository, where shared recipes arrive as issues.
    public static let repository = "matguitarist/Hangar"

    /// The game's setup as a recipe: settings only. Anything that names this Mac's user
    /// (a home folder path, the account name) is left out.
    public static func recipe(for game: Game, settings: BottleSettings?, runner: String?,
                              userName: String = NSUserName(), home: String = NSHomeDirectory()) -> Recipe {
        let slug = game.title.lowercased().map { $0.isLetter || $0.isNumber ? String($0) : "-" }.joined()
            .split(separator: "-").joined(separator: "-")
        var match = Recipe.Match(title: game.title)
        if let steamID = game.steamID {
            match.steamID = steamID
        } else if let exe = game.options.exe ?? game.exe, !exe.lowercased().hasSuffix(".lnk") {
            match.exe = exe.replacingOccurrences(of: "\\", with: "/").split(separator: "/").last.map(String.init)
        }
        var recipe = Recipe(id: slug.isEmpty ? "game" : slug, title: game.title, match: match)
        if let settings {
            recipe.graphics = settings.graphics == .auto ? nil : settings.graphics
            recipe.msync = settings.msync
            recipe.highResolution = settings.highResolution
            recipe.metalFX = settings.metalFX
            recipe.avx = settings.avx
        }
        let isPrivate = { (text: String) in Self.isPrivate(text, userName: userName, home: home) }
        let env = game.options.variables.filter { !$0.name.isEmpty && !isPrivate($0.value) && !isPrivate($0.name) }
        if !env.isEmpty { recipe.env = Dictionary(env.map { ($0.name, $0.value) }, uniquingKeysWith: { $1 }) }
        let arguments = ShellWords.split(game.options.arguments).filter { !isPrivate($0) }
        if !arguments.isEmpty { recipe.arguments = arguments.map(quoted).joined(separator: " ") }
        if let runner, !isPrivate(runner) { recipe.tested = runner }
        recipe.source = "Shared from Hangar"
        return recipe
    }

    /// True when the text names a path in a home folder or the account.
    static func isPrivate(_ text: String, userName: String, home: String) -> Bool {
        let lower = text.lowercased()
        if lower.contains("/users/") || lower.contains("\\users\\") || lower.contains("/home/") { return true }
        if !home.isEmpty, text.contains(home) { return true }
        if userName.count >= 3, lower.contains(userName.lowercased()) { return true }
        return false
    }

    static func quoted(_ word: String) -> String {
        word.contains(where: { $0 == " " || $0 == "'" || $0 == "\"" }) ? "'" + word.replacingOccurrences(of: "'", with: "'\\''") + "'" : word
    }

    /// The recipe as the JSON people paste into the manifest.
    public static func json(_ recipe: Recipe) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return (try? encoder.encode(recipe)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
    }

    /// A new issue on Hangar's GitHub, filled in with the recipe.
    public static func issueURL(_ recipe: Recipe) -> URL {
        let body = """
        A setup that works, shared from Hangar.

        \(recipe.notes ?? "What works, what doesn't (optional):")

        \u{60}\u{60}\u{60}json
        \(json(recipe))
        \u{60}\u{60}\u{60}
        """
        var components = URLComponents(string: "https://github.com/\(repository)/issues/new")!
        components.queryItems = [
            URLQueryItem(name: "title", value: "Recipe: \(recipe.title)"),
            URLQueryItem(name: "labels", value: "recipe"),
            URLQueryItem(name: "body", value: body),
        ]
        // URLComponents leaves "+" alone, which GitHub reads as a space.
        components.percentEncodedQuery = components.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        return components.url!
    }
}
