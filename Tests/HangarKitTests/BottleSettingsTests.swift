import Foundation
import Testing
@testable import HangarKit

/// The lines of a file that differ from another, ignoring the ones named.
private func lines(_ text: String, without keys: [String]) -> [Substring] {
    text.split(separator: "\n", omittingEmptySubsequences: false).filter { line in !keys.contains { line.contains("\"\($0)\"") } }
}

// S-010
@Test func readsTheSampleBottlesSettings() throws {
    let roots = try fixtureRoots()
    let steam = BottleSettings.read(bottle: roots.bottles.appending(path: "Steam"))
    #expect(steam == BottleSettings(graphics: .d3dMetal, msync: true, highResolution: false, metalFX: true, avx: false))
    #expect(BottleSettings.read(bottle: roots.bottles.appending(path: "Classics")) == BottleSettings())
}

@Test func eachSettingWritesItsKeyAndLeavesTheRestByteForByte() throws {
    let roots = try fixtureRoots()
    for name in ["Steam", "Classics"] {
        let bottle = roots.bottles.appending(path: name)
        let confBefore = try String(contentsOf: BottleSettings.conf(bottle), encoding: .utf8)
        let regBefore = try String(contentsOf: BottleSettings.userReg(bottle), encoding: .utf8)
        var settings = BottleSettings.read(bottle: bottle)
        for backend in GraphicsBackend.allCases {
            settings.graphics = backend
            try settings.write(bottle: bottle)
            #expect(BottleSettings.read(bottle: bottle).graphics == backend)
        }
        settings.msync.toggle(); settings.metalFX.toggle(); settings.avx.toggle(); settings.highResolution.toggle()
        let changed = try settings.write(bottle: bottle)
        #expect(changed.map(\.lastPathComponent) == ["cxbottle.conf", "user.reg"])
        #expect(BottleSettings.read(bottle: bottle) == settings)

        let conf = try String(contentsOf: BottleSettings.conf(bottle), encoding: .utf8)
        let keys = ["CX_GRAPHICS_BACKEND", "WINEMSYNC", "D3DM_ENABLE_METALFX", "ROSETTA_ADVERTISE_AVX"]
        #expect(lines(conf, without: keys) == lines(confBefore, without: keys))
        let reg = try String(contentsOf: BottleSettings.userReg(bottle), encoding: .utf8)
        #expect(reg.hasPrefix(regBefore.trimmingCharacters(in: .newlines).components(separatedBy: "[Software\\\\Wine\\\\Mac Driver]")[0]))
        #expect(reg.contains("\"RetinaMode\"=\"\(settings.highResolution ? "y" : "n")\""))
        #expect(reg.contains("[Software\\\\Wine\\\\Systray] 1783681125\n#time=1dd105b13caa636\n\"Hidden\"=dword:00000001"))
    }
}

@Test func writingTheSameSettingsChangesNoFile() throws {
    let roots = try fixtureRoots()
    let bottle = roots.bottles.appending(path: "Steam")
    #expect(try BottleSettings.read(bottle: bottle).write(bottle: bottle).isEmpty)
}

// S-011
@Test func aCopiedBottleGetsANewIDAndTheOriginalStaysAsItWas() async throws {
    let roots = try fixtureRoots()
    let original = roots.bottles.appending(path: "Steam")
    let before = try Data(contentsOf: BottleSettings.conf(original))
    let name = BottleCopy.name(for: "Vernal Edge", from: "Steam", in: roots.bottles)
    #expect(name == "Steam – Vernal Edge")
    let id = UUID()
    try await BottleCopy.copy(original, to: roots.bottles.appending(path: name), id: id)
    let copy = try ConfFile.read(BottleSettings.conf(roots.bottles.appending(path: name)))
    #expect(copy.value("BottleID", in: "Bottle") == id.uuidString)
    #expect(try Data(contentsOf: BottleSettings.conf(original)) == before)
    #expect(ConfFile(text: String(decoding: before, as: UTF8.self)).value("BottleID", in: "Bottle") == "11111111-2222-4333-8444-555555555555")
    #expect(BottleCopy.name(for: "Vernal Edge", from: "Steam", in: roots.bottles) == "Steam – Vernal Edge 2")
    // The copy holds the same games.
    let games = CrossOverScanner.scan(bottles: roots.bottles).games.filter { $0.bottle == name }
    #expect(games.contains { $0.title == "Vernal Edge" })
}

@Test func aMovedGameKeepsWhatThePersonDidAndTheCopysOtherGamesLeave() {
    var old = Game(id: "bottle:Steam:steam:1", title: "Vernal Edge", source: .crossOver, runner: .crossOver, bottle: "Steam")
    old.playtime = 600
    old.options.metalHUD = true
    let mate = Game(id: "bottle:Steam:steam:2", title: "Kynseed", source: .crossOver, runner: .crossOver, bottle: "Steam")
    let new = Game(id: "bottle:Copy:steam:1", title: "Vernal Edge", source: .crossOver, runner: .crossOver, bottle: "Copy")
    let mateCopy = Game(id: "bottle:Copy:steam:2", title: "Kynseed", source: .crossOver, runner: .crossOver, bottle: "Copy")
    var file = LibraryFile(games: [old, mate, new, mateCopy], collections: [GameCollection(name: "Fav", gameIDs: [old.id, mate.id])])
    file.moveGame(from: old.id, to: new.id)
    #expect(file.games.map(\.id) == [mate.id, new.id])
    #expect(file.games[1].playtime == 600 && file.games[1].options.metalHUD)
    #expect(file.collections[0].gameIDs == [new.id, mate.id])
    #expect(Set(file.removed.map(\.id)) == [old.id, mateCopy.id])
}

@Test func confFileAddsANewSectionAtTheEnd() {
    var conf = ConfFile(text: "[Bottle]\n\"A\" = \"1\"\n")
    conf.set("X", "2", in: "EnvironmentVariables")
    #expect(conf.text == "[Bottle]\n\"A\" = \"1\"\n[EnvironmentVariables]\n\"X\" = \"2\"\n")
    conf.set("X", nil, in: "EnvironmentVariables")
    #expect(conf.value("X", in: "EnvironmentVariables") == nil)
    #expect(conf.value("A", in: "Bottle") == "1")
}

@Test func regFileAddsAValueInsideItsKey() {
    var reg = RegFile(text: "WINE REGISTRY Version 2\n\n[Software\\\\Wine\\\\Mac Driver] 1\n#time=1\n\"A\"=\"b\"\n\n[Other] 2\n\"C\"=\"d\"\n")
    reg.setString("RetinaMode", "y", in: "Software\\Wine\\Mac Driver")
    #expect(reg.text == "WINE REGISTRY Version 2\n\n[Software\\\\Wine\\\\Mac Driver] 1\n#time=1\n\"A\"=\"b\"\n\"RetinaMode\"=\"y\"\n\n[Other] 2\n\"C\"=\"d\"\n")
    #expect(reg.string("retinamode", in: "software\\wine\\mac driver") == "y")
}
