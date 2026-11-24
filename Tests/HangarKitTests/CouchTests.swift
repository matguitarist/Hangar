import Foundation
import Testing
@testable import HangarKit

// S-028
@Test func arrowsMoveThroughTheRowsAndStopAtTheEdges() {
    var nav = CouchNavigator(rows: [["a", "b"], ["c", "d", "e", "f"]])
    #expect(nav.selected == "a")
    nav.move(.left)
    #expect(nav.selected == "a")
    nav.move(.right); nav.move(.right)
    #expect(nav.selected == "b")
    nav.move(.down)
    #expect(nav.selected == "d")
    nav.move(.right); nav.move(.right); nav.move(.right)
    #expect(nav.selected == "f")
    nav.move(.up)
    #expect(nav.selected == "b")
    nav.move(.up)
    #expect(nav.selected == "b")
}

@Test func emptyRowsAreLeftOutAndTheSelectionSurvivesNewRows() {
    var nav = CouchNavigator(rows: [[], ["c", "d"]])
    #expect(nav.rows.count == 1)
    nav.move(.right)
    nav.update(rows: [["d"], ["c", "d"]])
    #expect(nav.selected == "d" && nav.row == 0)
    nav.update(rows: [])
    #expect(nav.selected == nil)
    nav.move(.down)
    #expect(nav.selected == nil)
}

@Test func continuePlayingIsTheRecentGamesThenAllByName() {
    var a = Game(id: "a", title: "Zed", source: .steam)
    a.lastPlayed = Date(timeIntervalSince1970: 100)
    var b = Game(id: "b", title: "Alpha", source: .steam)
    b.lastPlayed = Date(timeIntervalSince1970: 200)
    let c = Game(id: "c", title: "Mid", source: .macApp)
    #expect(CouchNavigator.rows(for: [a, b, c]) == [["b", "a"], ["b", "c", "a"]])
}
