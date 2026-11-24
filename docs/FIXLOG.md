# Fix log

One entry per bug fixed: what broke, why, and the rule it teaches.

## 2026-11-23 Every game in the default bottle showed twice
CrossOver keeps `Bottles/default`, a symlink to the default bottle. The bottle scan listed it as a bottle of its own, so each game in the bottle named Steam also showed under "default". The scan now skips symlinks in the bottle folder; the sample library has the same `default` link, and `findsSteamGamesAndProgramsInBottles` failed before the fix.
Rule: when listing a folder of things, skip symlinks unless a link is a thing of its own; copy the real layout's links into the fixtures.

## 2026-11-23 Sidebar rows overlapped after a scan
With a Steam library on an unplugged drive, the Steam row's note ran over the CrossOver row, and Mac Apps sat on top of the first collection. The sidebar (an outline view under SwiftUI's List) keeps each row's height from its first layout; the cached library draws before the scan, and the note and bottles the scan adds made rows taller without a new layout. The List now takes an id made of the notes and bottles, so it lays out again when they change. The library snapshot showed the overlap before the fix and doesn't after.
Rule: a sidebar row whose height can change after it first draws (a note, a wrapped message) needs the list laid out again when that content changes; check sidebars in the first snapshot after a scan, not only after a page switch.

## 2026-11-24 Self-test failed on its second run
The check "a snapshot is saved before every change" passed once, then failed on every later run with "20 → 20". `tools/selftest.sh` cleared the store and the sample library between runs but not the snapshots folder next to the store, so snapshots piled up until the per-game limit of 20 kept the count from growing. Both scripts now remove every file a run leaves next to the store (snapshots, runner versions, the AppleGamingWiki cache), and the check compares the newest snapshot instead of counting them.
Rule: when a feature adds a file or folder next to the store, the self-test and snapshot scripts remove it at the start of a run; a check counts only what this run made.

## 2026-11-24 AppleGamingWiki said "no page" for games it has
Stardew Valley's page showed "AppleGamingWiki has no page for this game yet" though the page exists. Now and then the site answers a page request with its own "Page Not Found" web page (404, text/html) instead of the page; Hangar read every 404 as "the wiki has no such page" and kept that for a week. Now only the wiki's own answer (404 in wiki text) means no page; anything else is a failure that keeps the last good answer. "No page" is kept a day, not a week, for every web cache. A game whose page is named a little differently ("DRAGON QUEST XI S" for "Dragon Quest XI S") is found through the wiki's search, taking only a result with the same name apart from capitals and punctuation. `onlyTheWikisOwnNotFoundMeansNoPage`, `noPageIsAskedAgainTheNextDay` and `theWikisSearchFindsTheSameNameWrittenDifferently` failed before the fix; `liveAppleGamingWikiFindsPages` checks the real wiki.
Rule: a "not found" from a web service is an answer only when it comes in the service's own format; an error page is a failure, and a cached "nothing found" expires sooner than a cached answer.

## 2026-11-24 A test run turned off the real menu bar icon
Before S-026 shipped, a snapshot run turned "Show Hangar in the menu bar" off in the real app. The menu bar icon is hidden in test runs (its `isInserted` binding reads false there), and SwiftUI wrote that false back through the binding's setter into UserDefaults, which test runs share with the real app. The setter now ignores writes in a test run; the Settings snapshot showed the toggle off before the fix and on after, and `defaults read` finds no key after a snapshot and a self-test run.
Rule: test runs share the app's UserDefaults; a binding that hides something in a test run must not write its hidden state back, and any setting a test run changes is set in memory only.
