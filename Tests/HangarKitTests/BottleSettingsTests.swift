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
