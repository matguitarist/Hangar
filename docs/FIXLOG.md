# Fix log

One entry per bug fixed: what broke, why, and the rule it teaches.

## 2026-11-23 Every game in the default bottle showed twice
CrossOver keeps `Bottles/default`, a symlink to the default bottle. The bottle scan listed it as a bottle of its own, so each game in the bottle named Steam also showed under "default". The scan now skips symlinks in the bottle folder; the sample library has the same `default` link, and `findsSteamGamesAndProgramsInBottles` failed before the fix.
Rule: when listing a folder of things, skip symlinks unless a link is a thing of its own; copy the real layout's links into the fixtures.

## 2026-11-23 Sidebar rows overlapped after a scan
With a Steam library on an unplugged drive, the Steam row's note ran over the CrossOver row, and Mac Apps sat on top of the first collection. The sidebar (an outline view under SwiftUI's List) keeps each row's height from its first layout; the cached library draws before the scan, and the note and bottles the scan adds made rows taller without a new layout. The List now takes an id made of the notes and bottles, so it lays out again when they change. The library snapshot showed the overlap before the fix and doesn't after.
Rule: a sidebar row whose height can change after it first draws (a note, a wrapped message) needs the list laid out again when that content changes; check sidebars in the first snapshot after a scan, not only after a page switch.
