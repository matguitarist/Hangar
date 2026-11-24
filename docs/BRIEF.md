# Hangar

A native Mac app that puts every game on an Apple Silicon Mac in one library (native Mac games and Windows games run through CrossOver and other runners), and tunes, protects and fixes each one, for people who play on a Mac.

Free and open source (GPL-3), decided by the owner on 2026-11-23. The name Hangar is kept for now and may change. Research: `docs/research/game-managers.md`.

## Replaces
Opening Steam, CrossOver, Heroic and the Games app to find a game; looking up AppleGamingWiki and forums for the right settings; editing bottle settings by hand. Inspired by RHI (RankFTW/RHI) on Windows and Playnite.

## Main jobs
1. **Library**: see every game, Mac and Windows, with cover art, and launch it.
2. **Game page**: see whether it runs and how (status per method, recipe), and change its runner and settings safely.
3. **Fix**: when a game breaks, see why (crash readout), roll back its settings, or restore a save.

## Data
- Game: title, source (Steam Mac, Steam in a bottle, Mac app, added by hand), store id, path, exe, runner, cover, playtime, last played, collections.
- Runner: kind (native, CrossOver, Wine/GPTK, MacRunner), path, version, bottle or prefix.
- Recipe: game ids, runner, graphics backend, env vars, prefix changes (DLLs, registry, overrides, winetricks), launch args, last checked, result, source (AppleGamingWiki, Hangar, the owner).
- Snapshot: game, date, the settings and bottle files it saved, reason (before a change, before an update, a save backup).

## Platforms
Mac first: Swift 6 and SwiftUI with the house template (`new-mac-app`). No other system: the runners it drives exist only on the Mac.

## Shape
Sidebar window (library, collections, Running, Runners) with a game page beside it; a menu bar extra for quick launch in M5; a full-screen couch mode in M6. Local data, works offline (the recipe manifest and cover art are fetched and cached), no accounts. Developer ID, notarized, not sandboxed, free and open source (GPL-3).

## System hooks
Reads Steam, CrossOver and Heroic files; launches games with `Process` and their environment; GameController; power source and Low Power Mode; Shortcuts actions; Sparkle updates; LogKit for Wine logs.

## Reference
Playnite (library and couch mode), RHI (per-game setup from a remote manifest), CrossOver's bottle settings (`cxbottle.conf`), Heroic's `known_fixes.json` (recipe fields).

## Look
Native, cover art first, dark-friendly; accent system. English and French.

## Not in version one
Installing or buying games (Epic and GOG installs stay in Heroic; Hangar imports them later). Shipping a Wine or translation layer, or bundling D3DMetal. Anti-cheat and online games, ReShade and other mods, Parallels.
