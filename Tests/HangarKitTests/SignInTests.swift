import Foundation
import SteamKit
import Testing
@testable import HangarKit

// S-037 (how the log reads is SteamKit's test; this checks the bottle's Steam).
@Test func aSignedOutLogOverridesRememberedUsers() throws {
    let roots = try fixtureRoots()
    let steam = CrossOverScanner.steamFolder(bottle: roots.bottles.appending(path: "Steam"))
    #expect(Steam(root: steam).isSignedIn)
    let logs = steam.appending(path: "logs")
    try FileManager.default.createDirectory(at: logs, withIntermediateDirectories: true)
    try "[2026-10-07 10:00:00] [Logged Off, 0, 0] [U:1:0] Log session ended\n".write(to: logs.appending(path: "connection_log.txt"), atomically: true, encoding: .utf8)
    #expect(!Steam(root: steam).isSignedIn)
}
