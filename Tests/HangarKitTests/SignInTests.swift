import Foundation
import Testing
@testable import HangarKit

// S-037
@Test func aSessionThatEndedSignedOutNeedsASignIn() {
    let replaced = """
    [2026-11-24 06:00:56] [Logged On, 4, 15] [U:1:72413117] RecvMsgClientLogOnResponse() : processing complete
    [2026-11-24 08:56:29] [Logged On, 4, 15] [U:1:72413117] RecvMsgClientLoggedOff('Session Replaced')
    [2026-11-24 08:57:16] [Logged Off, 0, 0] [U:1:72413117] Log session ended
    """
    #expect(!SteamScanner.lastSessionSignedOut(replaced))
    let signedOut = replaced + "\n[2026-11-24 09:01:00] [Connecting, 0, 0] [U:1:0] Log session ended\n"
    #expect(SteamScanner.lastSessionSignedOut(signedOut))
    #expect(!SteamScanner.lastSessionSignedOut(""))
}

@Test func aSignedOutLogOverridesRememberedUsers() throws {
    let roots = try fixtureRoots()
    let steam = CrossOverScanner.steamFolder(bottle: roots.bottles.appending(path: "Steam"))
    #expect(SteamScanner.isSignedIn(steamRoot: steam))
    let logs = steam.appending(path: "logs")
    try FileManager.default.createDirectory(at: logs, withIntermediateDirectories: true)
    try "[2026-10-07 10:00:00] [Logged Off, 0, 0] [U:1:0] Log session ended\n".write(to: logs.appending(path: "connection_log.txt"), atomically: true, encoding: .utf8)
    #expect(!SteamScanner.isSignedIn(steamRoot: steam))
}
