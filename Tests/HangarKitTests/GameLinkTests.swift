import Foundation
import Testing
@testable import HangarKit

// S-020
@Test func linksComeFromTheStoreIDWhenThereIsOne() {
    let links = GameLinks.links(title: "Hollow Knight", steamID: "367520", wikiPage: "Hollow_Knight")
    let urls = Dictionary(uniqueKeysWithValues: links.map { ($0.site, $0.url.absoluteString) })
    #expect(links.map(\.site) == [.appleGamingWiki, .pcGamingWiki, .codeWeavers, .protonDB, .steam])
    #expect(urls[.appleGamingWiki] == "https://www.applegamingwiki.com/wiki/Hollow_Knight")
    #expect(urls[.pcGamingWiki] == "https://www.pcgamingwiki.com/api/appid.php?appid=367520")
    #expect(urls[.protonDB] == "https://www.protondb.com/app/367520")
    #expect(urls[.steam] == "https://store.steampowered.com/app/367520/")
    #expect(urls[.codeWeavers] == "https://www.codeweavers.com/compatibility?name=Hollow%20Knight")
}

@Test func withoutAStoreIDLinksSearchByTitle() {
    let links = GameLinks.links(title: "Moonlit Harbor: R&D #2", steamID: nil)
    let urls = Dictionary(uniqueKeysWithValues: links.map { ($0.site, $0.url.absoluteString) })
    #expect(links.allSatisfy(\.isSearch) && links.count == 4)
    #expect(urls[.pcGamingWiki] == "https://www.pcgamingwiki.com/w/index.php?search=Moonlit%20Harbor:%20R%26D%20%232")
    #expect(urls[.protonDB] == "https://www.protondb.com/search?q=Moonlit%20Harbor:%20R%26D%20%232")
    #expect(urls[.appleGamingWiki]?.hasPrefix("https://www.applegamingwiki.com/w/index.php?search=") == true)
    // A store id that isn't a number is ignored.
    #expect(GameLinks.links(title: "X", steamID: "../x").count == 4)
}
