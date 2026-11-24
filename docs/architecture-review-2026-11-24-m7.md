# Architecture review, 2026-11-24 (end of M7)

M7 added the Storage and Health pages, frame caps, bottle drift after a runner update, smart filters,
play sessions, launch records, and library export. Each rule lives in HangarKit with a test
(`StorageScanner`, `LibraryHealth`, `FrameCap`, `RunnerVersions.drifts`, `GameFilter`, `PlayHistory`,
`LaunchRecord`, `LibraryExport`); the app files are thin `AppModel+…` extensions and one view each.
No file is over 450 lines.

## The person's data on a game, kept in one place  [Strong, done]
Playtime, sessions, launch records, cover, options and the added date were copied field by field in
`LibraryFile.merge` and `moveGame`; M7 added three fields and each had to be added twice. A forgotten one
would lose data on the next rescan. Now `Game.keepPersonalData(from:)` holds the list, with a test that a
rescan keeps every field. The import's merge rules differ on purpose (higher playtime wins) and stay in
`LibraryFile.importing`.

## AppModel's page state  [Worth exploring]
Storage, Health, import and filter state each added one or two properties to `AppModel` (73 stored
properties now). Page models (`StorageModel`, `HealthModel`) would shrink it; they'd need the library,
roots and log, so wait until a page grows past one screen of logic.

## Health computed on demand  [Considered, not recommended]
`checkHealth` runs after each scan and on the page; a live computed property would recheck files on every
redraw.

## Carried over
A runner protocol (M5), couch state (M6): unchanged.
