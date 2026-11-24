# Fix log

One entry per bug fixed: what broke, why, and the rule it teaches.

## 2026-11-23 Every game in the default bottle showed twice
CrossOver keeps `Bottles/default`, a symlink to the default bottle. The bottle scan listed it as a bottle of its own, so each game in the bottle named Steam also showed under "default". The scan now skips symlinks in the bottle folder; the sample library has the same `default` link, and `findsSteamGamesAndProgramsInBottles` failed before the fix.
Rule: when listing a folder of things, skip symlinks unless a link is a thing of its own; copy the real layout's links into the fixtures.
