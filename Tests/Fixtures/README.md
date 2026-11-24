# Sample library

Copied from the layout of a real Mac: a Steam folder with two library folders (one on a drive that isn't connected), CrossOver bottles, Mac apps, and the games Heroic installed (`Heroic/` names them, `Games/` holds them). `Steam/appcache/stats` holds made-up achievement files for Hollow Knight (40 achievements, 12 unlocked), written in Steam's binary KeyValues format by a script; the account id 10001 is fake.
The self-test and snapshot mode copy this folder to `<store>-run/fixtures` in /tmp and replace @ROOT@ with that folder. Unit tests read it in place.
