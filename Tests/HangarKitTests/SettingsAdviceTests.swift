import Foundation
import Testing
@testable import HangarKit

// S-034
@Test func theWikiNotesSuggestWhatTheyRecommend() {
    let s = SettingsAdvice.suggestions(current: BottleSettings(), crossOverNotes: "Runs with D3DMetal. Set MSync on; see the CrossOver page.", api: nil)
    #expect(s.map(\.change) == [.graphics(.d3dMetal), .msync])
    #expect(s.first?.reason == .wikiNote("Runs with D3DMetal"))
    #expect(s.last?.reason == .wikiNote("Set MSync on"))
}

@Test func aWarningIsNeverASuggestion() {
    let notes = "DXVK crashes on launch. Doesn't work with DXMT; the intro is black. Use D3DMetal."
    #expect(SettingsAdvice.suggestions(current: BottleSettings(), crossOverNotes: notes, api: nil).map(\.change) == [.graphics(.d3dMetal)])
    // Two backends recommended: they disagree, so no graphics advice.
    #expect(SettingsAdvice.suggestions(current: BottleSettings(), crossOverNotes: "Runs with DXMT. Also fine with DXVK.", api: nil).isEmpty)
}

@Test func theDirectXVersionIsARuleOnlyWhenTheNotesSayNothing() {
    let dx9 = GameAPI(direct3D: [9])
    #expect(SettingsAdvice.suggestions(current: BottleSettings(), crossOverNotes: nil, api: dx9).first?.change == .graphics(.dxvk))
    #expect(SettingsAdvice.suggestions(current: BottleSettings(), crossOverNotes: nil, api: GameAPI(direct3D: [10])).first?.reason == .directX(10))
    // Direct3D 11 and 12: CrossOver's Auto already picks D3DMetal.
    #expect(SettingsAdvice.suggestions(current: BottleSettings(), crossOverNotes: nil, api: GameAPI(direct3D: [9, 11])).isEmpty)
    // Notes win over the rule.
    #expect(SettingsAdvice.suggestions(current: BottleSettings(), crossOverNotes: "Runs with DXMT.", api: dx9).map(\.change) == [.graphics(.dxmt)])
}

@Test func whatIsAlreadySetIsNotSuggested() {
    let current = BottleSettings(graphics: .d3dMetal, msync: true)
    #expect(SettingsAdvice.suggestions(current: current, crossOverNotes: "Runs with D3DMetal. Set MSync on.", api: nil).isEmpty)
}

@Test func theAPIBoxIsRead() {
    let source = """
    {{API
    |direct3d versions      = 9.0c, 11
    |direct3d notes         =
    |windows 32-bit exe     = false
    |windows 64-bit exe     = true
    }}
    """
    #expect(GameAPI.parse(source) == GameAPI(direct3D: [9, 11], windows64: true, windows32: false))
    #expect(GameAPI.parse("{{API\n|direct3d versions = \n|windows 64-bit exe = unknown\n}}") == nil)
}
