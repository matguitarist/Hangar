import Foundation

/// The sample library in Tests/Fixtures, copied to a folder in /tmp for a test run.
/// Its .vdf files name their own folder as @ROOT@, replaced here with the copy's path.
public enum FixtureLibrary {
    public static func install(from source: URL, to target: URL) throws -> LibraryRoots {
        let fm = FileManager.default
        try? fm.removeItem(at: target)
        try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fm.copyItem(at: source, to: target)
        if let files = fm.enumerator(at: target, includingPropertiesForKeys: nil) {
            for case let file as URL in files where file.pathExtension == "vdf" {
                let text = try String(contentsOf: file, encoding: .utf8)
                if text.contains("@ROOT@") {
                    try text.replacingOccurrences(of: "@ROOT@", with: target.path).write(to: file, atomically: true, encoding: .utf8)
                }
            }
        }
        return roots(at: target)
    }

    /// The fixture's folders. Its CrossOver.app is missing on purpose: Windows games can't start.
    public static func roots(at folder: URL) -> LibraryRoots {
        LibraryRoots(steam: folder.appending(path: "Steam"), bottles: folder.appending(path: "Bottles"),
                     crossOverApp: nil, appFolders: [folder.appending(path: "Applications")], ownBundleID: "com.mathieuares.hangar")
    }
}
