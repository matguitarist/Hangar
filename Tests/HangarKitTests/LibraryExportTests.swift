import Foundation
import Testing
@testable import HangarKit

// S-046
@Test func importMergesByGameID() throws {
    let folder = FileManager.default.temporaryDirectory.appending(path: "HangarTests-export-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let coverFile = folder.appending(path: "custom-1.png")
    try Data("png".utf8).write(to: coverFile)

    var there = LibraryFile()
    var a = Game(id: "a", title: "A", source: .macApp)
    a.playtime = 7200
    a.customCover = coverFile.path
    a.options.arguments = "-windowed"
    var b = Game(id: "b", title: "B", source: .macApp)
    b.playtime = 100
    let gone = Game(id: "gone", title: "Gone", source: .macApp)
    there.games = [a, b, gone]
    there.collections = [GameCollection(name: "Favorites", gameIDs: ["a"]), GameCollection(name: "Co-op", gameIDs: ["b"])]
    let data = try LibraryExport(library: there).encoded()

    var here = LibraryFile()
    var hereA = Game(id: "a", title: "A", source: .macApp)
    hereA.playtime = 60
    var hereB = Game(id: "b", title: "B", source: .macApp)
    hereB.playtime = 500
    hereB.options.arguments = "-mine"
    here.games = [hereA, hereB]
    here.collections = [GameCollection(name: "favorites", gameIDs: ["b"])]
    let covers = folder.appending(path: "Covers")
    let summary = here.importing(try LibraryExport.decode(data), coversFolder: covers)

    #expect(summary == ImportSummary(games: 3, collections: 2))
    #expect(here.games.first { $0.id == "a" }?.playtime == 7200)
    #expect(here.games.first { $0.id == "b" }?.playtime == 500)
    #expect(here.games.first { $0.id == "a" }?.options.arguments == "-windowed")
    #expect(here.games.first { $0.id == "b" }?.options.arguments == "-mine")
    let cover = try #require(here.games.first { $0.id == "a" }?.customCover)
    #expect(cover.hasPrefix(covers.path) && FileManager.default.contents(atPath: cover) == Data("png".utf8))
    #expect(here.removed.map(\.id) == ["gone"])
    #expect(here.collections.count == 2)
    #expect(here.collections.first { $0.name == "favorites" }?.gameIDs == ["b", "a"])
}
