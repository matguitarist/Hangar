# Mac game managers and Windows-game runners

Research for Hangar. Done 2026-11-23.
[V] verified in a source, [K] from knowledge, [U] unverified, test first.

Question: what makes the best game library and manager on an Apple Silicon Mac, and which runners can it drive?
Decision it informs: what goes in version one, how the app launches Windows games, and where recipes come from.

## Findings

### Market
- Apple Games (macOS 26) is free and built in, and covers App Store and Arcade games plus Game Center. It does not reliably list Steam, GOG or Epic games, and you can't add a game by hand. [V](https://forums.macrumors.com/threads/is-there-any-way-to-force-steam-games-into-the-games-app.2469109/) [V](https://support.apple.com/guide/games/devbdb12f8d7/mac)
- CrossOver 26.3 costs $74 a year or $494 for life. It ships Wine 11, D3DMetal 3.0 and DXMT, and since version 25 it picks a graphics backend per game automatically. [V](https://www.codeweavers.com/crossover/changelog) [V](https://www.codeweavers.com/store)
- Heroic 2.22.4 is free and GPL-3. It's an Electron app for Epic, GOG and Amazon games, with GPTK, Wine, DXMT and CrossOver runners. Steam install was removed on the Mac in 2.19. [V](https://github.com/Heroic-Games-Launcher/HeroicGamesLauncher/releases)
- Mythic is a native Swift Epic launcher built on GPTK. It has stalled: the last pre-release was in Dec 2025 and the last commit in Feb 2026. [V](https://github.com/MythicApp/Mythic/releases)
- Whisky was archived in May 2025. A fork, frankea/Whisky, is active (3.10.x, Nov 2026). [V](https://github.com/Whisky-App/Whisky) [V](https://frankea.github.io/Whisky/)
- Sikarugir, the former Kegworks and successor to Wineskin, wraps each game as its own .app. It's installed with Homebrew from the Terminal. [V](https://github.com/Sikarugir-App/Sikarugir)
- Porting Kit (pay what you want) has more than 300 install scripts. 7.0.2 added DXMT. [V](https://paulthetall.itch.io/porting-kit)
- MacRunner 1.1.4 (Nov 20, 2026) is a runner built on FEX, Wine and Metal, with its own library. The app's source isn't public (license "Other"), while its HyperBridge engine is MIT. It has no CLI or URL scheme. [V](https://github.com/t0b1kent/macrunner-app)
- Playnite (Windows, 10.65) is the model for a unified library: plugins for each store, metadata, a fullscreen controller mode. [V](https://github.com/JosefNemec/Playnite/releases)
- RHI (Windows) finds games across 8 stores, gets game data from PCGamingWiki, and ships a remote manifest with per-game setup. [V](https://github.com/RankFTW/RHI)

### Data sources for recipes
- AppleGamingWiki gives a status per game for each method: native, Rosetta 2, the iPad version, CrossOver, Wine, Parallels, Windows 10 ARM and Linux ARM. Each status has notes naming the Mac, macOS version and method. License CC BY-NC-SA 3.0. [V](https://www.applegamingwiki.com/wiki/M1_compatible_games_master_list)
- Its query API refuses anonymous requests ("permissiondenied"). Page source can be read through `action=parse`. robots.txt: `search=yes, ai-train=no, use=reference`. [V] probe on 2026-11-23
- CodeWeavers' game pages are behind a Cloudflare check, and robots.txt asks for 100 seconds between requests. No open license, so link to it and don't copy. [V] probe on 2026-11-23
- PCGamingWiki is run by the same people under the same license, and lists save-game and config locations for each game. [K]
- Heroic ships `known_fixes.json` with fixes per store id: winetricks, envVariables, runInPrefix and notes. It's GPL-3, so we can learn from the format but not copy the data into a non-GPL app. [V] the file on this Mac

### Platform (this Mac: M4, macOS 27.2.1, CrossOver 26.3, Heroic, Steam)
- CrossOver keeps per-bottle settings in `~/Library/Application Support/CrossOver/Bottles/<bottle>/cxbottle.conf`, in its `[EnvironmentVariables]` section: `CX_GRAPHICS_BACKEND` (d3dmetal, dxmt, dxvk, wined3d; absent means Auto), `WINEMSYNC`, `D3DM_ENABLE_METALFX`, `DXMT_ENABLE_NVEXT`. [V] Steam bottle on this Mac, [V](https://github.com/stoicswe/Endfield_FineWine/pull/15)
- CrossOver's command-line tools are `cxstart`, `cxbottle` and `wine --bottle` in `CrossOver.app/Contents/SharedSupport/CrossOver/bin`. Heroic launches through `wine --bottle`. They are not officially documented. [V](https://support.codeweavers.com/run-a-windows-app-from-terminal) [V](https://raw.githubusercontent.com/Heroic-Games-Launcher/HeroicGamesLauncher/main/src/backend/launcher.ts)
- CrossOver applies settings to the whole bottle, so different settings per game means one bottle per game, or per group of games with the same needs. [V](https://support.codeweavers.com/miscellanous/advanced-settings-in-crossover-mac)
- Steam: `steamapps/libraryfolders.vdf` and `appmanifest_<id>.acf`, the same files for Mac Steam and for Windows Steam inside a bottle. This Mac has 5 Mac games in two libraries and 7 Windows games in the CrossOver Steam bottle. [V] on this Mac
- DLSS through MetalFX needs `D3DM_ENABLE_METALFX=1`, DLLs copied into the prefix, a registry key and DLL overrides, not just an environment variable. [V](https://github.com/Heroic-Games-Launcher/HeroicGamesLauncher/pull/5984)
- `ROSETTA_ADVERTISE_AVX=1` [V](https://github.com/Heroic-Games-Launcher/HeroicGamesLauncher/issues/4193). `MTL_HUD_ENABLED=1` [K].
- Game Mode only applies to an `.app` with a games category. A wrapper bundle around Wine's loader turns it on, but frame rates didn't go up in a test on macOS 27.0.1. [V](https://github.com/yaagl/yet-another-anime-game-launcher/issues/773)
- Controllers: GameController's `GCController`, with `shouldMonitorBackgroundEvents` to keep input after the app is in the background. Power: `isLowPowerModeEnabled` and `IOPSNotificationCreateRunLoopSource`. [K]
- Sandbox: Wine can't run under the App Sandbox, and the app must read other apps' folders. So it ships with Developer ID, notarized, not on the Mac App Store. [K]
- D3DMetal license: redistribution is non-commercial only, the framework in its entirety, Apple hardware only. Don't bundle it. [V](https://github.com/dbc-hbin/d3dmetal-redistributable)
- Steam achievements are in binary KeyValues files under `appcache/stats`, an undocumented format. [V] community sources only

## Likes and dislikes

| App | People like | People dislike | Sources |
| --- | --- | --- | --- |
| CrossOver | Runs games with no tinkering (automatic backend); the fallback when free tools fail; regular fixes; trial and compatibility database | Updates break games; a second Windows Steam knocks native Steam offline; refunds refused and slow support; anti-cheat games and battery drain; price | [betanews](https://betanews.com/article/crossover-25-makes-gaming-on-macos-and-linux-even-better-could-it-help-gamers-ditch-windows-11/), [HN](https://news.ycombinator.com/item?id=45908175), [Trustpilot](https://www.trustpilot.com/review/www.codeweavers.com), [machow2](https://machow2.com/crossover-mac-review/) |
| Whisky | Free, one-click bottles; fast; native SwiftUI | Abandoned; Steam error 0x3008; registry edits from a wiki | [GitHub](https://github.com/Whisky-App/Whisky), [Steam](https://steamcommunity.com/discussions/forum/2/640179666902095970), [HN](https://news.ycombinator.com/item?id=43631399) |
| Sikarugir | Free, runs most things; choice of D3DMetal, DXMT or DXVK; one .app per game | Installed from the Terminal; Steam breaks on every Steam update; lag spikes; crashes that freeze the Mac | [HN](https://news.ycombinator.com/item?id=47341409), [HN](https://news.ycombinator.com/item?id=50112600), [itch](https://itch.io/post/14333215) |
| Porting Kit | Install scripts for more than 300 games; guided install | Hangs creating a prefix; slow Steam downloads; scripts go stale | [itch](https://paulthetall.itch.io/porting-kit), [FAQ](https://www.paulthetall.com/faq/) |
| Heroic | Choice of layer and version; free front end for Epic and GOG; better gamepad navigation in 2.19 | Every game needs manual tuning; updates loop the Play button; old bundled Wine; Steam install removed; Electron | [wiki](https://github.com/Heroic-Games-Launcher/HeroicGamesLauncher/wiki/Using-Heroic-on-a-Mac-computer), [#5278](https://github.com/Heroic-Games-Launcher/HeroicGamesLauncher/issues/5278), [alternativeto](https://alternativeto.net/news/2026/1/heroic-games-launcher-2-19-brings-zoom-games-integration-dxmt-support-on-macos-and-more) |
| Mythic | Native Mac interface; game containers without the Terminal; imports from other launchers | Epic sign-in fails; games missing or won't launch; Steam broken; alpha | [GitHub](https://github.com/MythicApp/Mythic/issues), [machow2](https://machow2.com/best-way-play-windows-games-mac/) |
| Apple Games | Light; controller and overlay; Game Center and Arcade in one place | Steam games missing; buggy controller navigation; can't uninstall | [MacRumors](https://forums.macrumors.com/threads/thoughts-on-games-app.2472295/), [Macworld](https://www.macworld.com/article/2809636/apples-latest-gaming-efforts-wont-move-the-needle.html) |
| Playnite | One library across stores; free couch mode; themes; automatic art, data kept locally | Learning curve; Windows only; P11 keeps slipping | [playnite.link](https://playnite.link/), [alternativeto](https://alternativeto.net/software/playnite/about) |
| MacRunner | (Too new for reviews.) Claims DX12 without Rosetta, about 45 fps in Elden Ring on an M1 Pro against 25 with CrossOver | One developer, experimental, needs macOS 26.5 | [GitHub](https://github.com/t0b1kent/macrunner-app) |

Patterns. Must have: games run with no tinkering; one library for everything; native Mac feel; free couch mode. Our chances to do better: updates break games (snapshot and roll back), manual tuning per game (recipes), Steam games missing (reliable scanning), clashes between two Steam clients (launch from one library).

## Feature matrix

| Feature | Apple Games | CrossOver | Heroic | Playnite | RHI | Version one? |
| --- | --- | --- | --- | --- | --- | --- |
| Native Mac games (Steam, apps) in one library | partly | no | no | n/a | n/a | yes, M1 |
| Windows games in bottles | no | yes | yes | n/a | n/a | yes, M1 (find), M2 (run) |
| Add a game by hand | no | yes | yes | yes | yes | yes, M1 |
| Cover art | yes | no | yes | yes | yes | yes, M1 |
| Playtime | partly | no | yes | yes | yes | yes, M1 |
| Graphics backend per game | n/a | per bottle | by Wine build | n/a | n/a | yes, M2 |
| MSync, High Resolution, AVX, MetalFX | n/a | yes | partly | n/a | n/a | yes, M2 |
| Metal HUD | yes, system | env only | showFps | n/a | n/a | yes, M2 |
| Frame cap | no | no | DXVK only | n/a | yes | later (needs a test) |
| Compatibility status before you buy | no | database | links | n/a | manifest | yes, M3 |
| Recipes from a remote manifest | no | closed DB | known_fixes | n/a | yes | yes, M3 |
| Snapshot settings and roll back | no | no | no | no | backups | yes, M3 |
| Save backup | iCloud for App Store games | no | Epic/GOG cloud | no | no | yes, M4 |
| Crash readout | no | no | logs | no | no | yes, M4 |
| Battery profiles | no | no | no | no | no | yes, M5 |
| Menu bar launcher, Shortcuts | no | no | no | no | tray | yes, M5 |
| Couch mode with controller | yes | no | partly | yes | yes | M6 |
| Achievements | Game Center | no | no | plugin | yes | M6, experimental |
| Epic and GOG install | no | no | yes | plugin | n/a | later (import Heroic installs) |
| HDR for Wine games | no | no | flag | n/a | yes | later (needs a test) |
| ReShade, mods | no | no | no | n/a | yes | later |

## Decisions

1. Hangar is a library and manager. It does not ship its own Wine or translation layer; it drives runners the user already has (CrossOver first, then GPTK/Wine builds, MacRunner as "open in MacRunner"), because the gap is the library layer [V Market] and D3DMetal can't be bundled in a paid app [V license].
2. Free and open source, under GPL-3 (decided by the owner, 2026-11-23). This lets Hangar use AppleGamingWiki's CC BY-NC-SA data with credit, and fills the free, native slot left by Whisky and Mythic [V Market]. Planned test: ask AppleGamingWiki's admins for an export or API access before scraping.
3. Developer ID, notarized and non-sandboxed, released with tools/release.sh and Sparkle, because Wine can't run sandboxed and the app reads other apps' folders [K].
4. CrossOver is the first runner, driven through `cxbottle.conf` and `wine --bottle`, because that's where paying Mac gamers already are and Heroic proves it works [V]. Planned test: a probe that changes `CX_GRAPHICS_BACKEND` in a copied bottle and launches a game with `wine --bottle`.
5. Changing a game's settings never touches a shared bottle without asking: Hangar offers to give the game its own bottle (a copy), because CrossOver's settings apply per bottle [V].
6. Every settings change is snapshotted first and can be rolled back, because updates breaking games is the top pain across every runner [V Reviews].
7. Recipes are data, in a JSON manifest in Hangar's repo, versioned, each with the date it was last checked and how well the game ran. The starting data is AppleGamingWiki's status per method, with a link back [V]. Recipe fields: runner, backend, env vars, DLL copies, registry keys, DLL overrides, winetricks, launch args, exe [V MetalFX PR].
8. Steam is read from its own files (Mac Steam and Windows Steam in bottles), not from the Games app, because finding every game is what people judge a library on [V Reviews B].
9. Frame cap, HDR for Wine games, Game Mode wrappers and achievements are experiments, not promises [U].

## Open questions

- [V] partly: a Steam game in a bottle that uses steam_api does not start without the Windows Steam client. Details:
  2026-11-23 probe on this Mac (CrossOver 26.3, bottle Steam, Vernal Edge, Steam app 1546710, which ships steam_api64.dll):
  - Launched directly with `wine --bottle Steam --cx-app VernalEdge.exe`: quit after about 8 s with exit code 9, without opening Steam.
  - Launched with `steam.exe -silent -applaunch 1546710`: Windows Steam started (the first process exits 42, which is Steam relaunching itself) but the game never started in 2 minutes. connection_log.txt shows Steam logged off ([U:1:0]); the last session ended with a sign-out on 2026-10-07, so -applaunch waits for a sign-in that -silent hides.
  - Steam was closed afterwards with `steam.exe -shutdown`.
  So far: Steam games in a bottle need the Windows Steam client, signed in.
  2026-11-23, signed in to the bottle's Steam:
  - `steam.exe -applaunch 1546710` started Vernal Edge in about 3 s; the title screen showed and the game was still running 19 s later. [V]
  - `wine --bottle Steam --cx-app VernalEdge.exe` with Steam running and signed in: the game did not start (no process within 30 s). [V]
  - Every game in this bottle ships steam_api, so a DRM-free game starting directly is still untested.
  Decision: Steam games in a bottle always launch with `steam.exe -applaunch <appid>`. The launcher process exits right away (exit 42 is Steam relaunching itself), so Hangar tracks "running" and playtime by watching for the game's exe process, not the launch command.
- [U] Do CrossOver updates rewrite `cxbottle.conf`'s [EnvironmentVariables]? Test: change a value, update CrossOver, diff the file.
- [U] Will AppleGamingWiki allow an export or API access? Ask before parsing pages.
- [U] Is there a frame cap that works under D3DMetal? (DXVK has `dxvk.conf` maxFrameRate; DXMT is unknown.)
- [U] Can MacRunner add a URL scheme or CLI? Its issue #3 asks for external launching.
- [U] Can Hangar read Steam achievements from `appcache/stats`? Probe with one game.
