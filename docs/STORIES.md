# Hangar — User stories

Hangar puts every game on the Mac in one library and tunes, protects and fixes each one. The brief is `docs/BRIEF.md`, the research `docs/research/game-managers.md`. The roadmap is "Hangar Roadmap" in Thimble.
Snapshot pages are named in `Screens:` and are built by snapshot mode (`tools/snap.sh`). Test data: the sample library in `Tests/Fixtures/` (Steam files, a CrossOver bottle, Mac apps), copied from this Mac's real layout.

---

## M1 One library (0.1.0)

### S-001 Find native Steam games
As the user, I open Hangar and see the Mac games from every Steam library on this Mac.
Screens: library
Acceptance:
- [unit] Reads `libraryfolders.vdf` and each `appmanifest_<id>.acf` from every library folder, including libraries on other drives.
- [unit] A library folder that is missing (an unplugged drive) is skipped and noted, not an error.
- [self] The sample library shows its Steam games with their names.
UX:
- Flow: launch Hangar → library scans in the background, cached games show at once → new games fade in; View › Refresh Library (⌘R) scans again
- Surface: sidebar page "All Games" (a place people come back to), cover grid; "Steam" under Sources in the sidebar
- States: empty "No Games Found" with "Add Game…" and "Choose Steam Folder…"; loading "Looking for games…" in the toolbar only past half a second; error inline "The library on Data isn't connected. Its games come back when the drive is." on the Steam source row; too much: thousands of games scroll smoothly, long titles truncate with the full title in a tooltip
- Words: "All Games" / « Tous les jeux », "Refresh Library" / « Actualiser la bibliothèque », "Steam" source
- Access: arrow keys move through the grid, Return launches (S-006), Space shows the game page; VoiceOver reads "Hollow Knight, Steam, played 3 hours"
Status: done

### S-002 Find Windows games in CrossOver bottles
As the user, I see the Windows games installed in my CrossOver bottles, Steam games inside a bottle included, marked with the bottle they live in.
Screens: library
Depends: S-001
Acceptance:
- [unit] Reads the bottle folder from `com.codeweavers.CrossOver.plist` (`BottleDir`), or the default folder.
- [unit] Finds Steam manifests inside a bottle's `drive_c`, and the programs CrossOver lists for the bottle.
- [self] The sample bottle's games show with a "CrossOver · Steam" badge.
UX:
- Flow: same scan as S-001 → bottle games show with a source badge → the "CrossOver" source in the sidebar lists them by bottle
- Surface: same grid; a small badge on the cover "Windows" with the bottle name in the tooltip; sidebar source "CrossOver" expands to its bottles
- States: CrossOver not installed: the source isn't shown; empty bottle: "No games in this bottle" in its page; error inline "Hangar can't read the bottle Steam. Open it once in CrossOver, then refresh."
- Words: "Bottle" (a CrossOver bottle) / « Bouteille », badge "Windows" / « Windows », tooltip "Runs in CrossOver, bottle Steam" / « S'exécute dans CrossOver, bouteille Steam »
- Access: the badge is text, not color alone; VoiceOver adds "Windows game, bottle Steam"
Status: done

### S-003 Find Mac apps that are games
As the user, I see the games in /Applications and ~/Applications: App Store and Arcade games and emulators.
Screens: library
Depends: S-001
Acceptance:
- [unit] An app counts as a game when its `LSApplicationCategoryType` is a games category.
- [self] The sample games appear; a non-game app in the same folder does not.
UX:
- Flow: same scan → Mac apps that are games join the grid under the source "Mac Apps"
- Surface: same grid; sidebar source "Mac Apps"
- States: none found: the source isn't shown; an app moved to the Trash disappears at the next scan
- Words: "Mac Apps" / « Apps Mac »
- Access: as S-001
Status: done

### S-004 Add a game by hand
As the user, I drag an .app or a Windows .exe onto the window, or use File › Add Game…, and it joins the library; for an .exe I pick the bottle it runs in.
Screens: library, add-game
Depends: S-002
Acceptance:
- [self] Dropping an .app adds it; dropping an .exe asks for the bottle, then adds it.
- [self] A game removed from the library can be brought back from Settings.
- [unit] Adding the same path twice doesn't make two games.
UX:
- Flow: drag an .app or .exe onto the window, File › Add Game… (⌘N) or toolbar + → for an .app it's added and selected; for an .exe a sheet asks for the bottle → Add → the game is selected; Escape cancels; ⌘Z removes it again
- Surface: sheet "Add Windows Game" only for an .exe (one short task that must finish); nothing for an .app
- States: the drop target highlights while dragging; error inline in the sheet "This file isn't a Windows program." ; already in the library: the existing game is selected, no duplicate; removed games: Settings › Library › "Removed Games" with "Restore"
- Words: "Add Game…" / « Ajouter un jeu… », sheet title "Add Windows Game" / « Ajouter un jeu Windows », "Bottle" picker, buttons "Add" / « Ajouter » and "Cancel" / « Annuler », context menu "Remove from Library" / « Retirer de la bibliothèque » (the game stays on disk), tooltip on + "Add a game (⌘N)" / « Ajouter un jeu (⌘N) »
- Access: the picker is first in the sheet, Return adds, Escape cancels; drag and drop has a menu equivalent
Status: done

### S-005 Cover art
As the user, I see each game's cover art: Steam's art for Steam games, the app icon for other Mac games, a generated cover otherwise; I can pick my own image.
Screens: library
Depends: S-001
Acceptance:
- [unit] Steam art is fetched once from Steam's public image URL and cached; offline, the cache or the generated cover is used.
- [snap] The library grid in light and dark, with real and generated covers.
UX:
- Flow: covers load as the grid scrolls, cached first → context menu "Choose Cover…" → file picker → the cover changes; "Reset Cover" goes back
- Surface: inline in the grid; file picker for a custom image
- States: loading: a generated cover (title on a color from the name), never a spinner per cover; offline: cache or generated cover; error: the generated cover stays, nothing to read
- Words: "Choose Cover…" / « Choisir une couverture… », "Reset Cover" / « Rétablir la couverture »
- Access: covers are decorative for VoiceOver; the title is always read
Status: done

### S-006 Launch a game and count playtime
As the user, I double-click a game, or press Return, and it starts through its runner; Hangar shows it as running and adds the time to its playtime.
Screens: library, game-page
Depends: S-001
Acceptance:
- [self] A native game starts with `open`; a bottle game starts with CrossOver's `wine --bottle <bottle> --cx-app <exe>`.
- [self] While it runs, the game shows a running badge and a Stop button; when it quits, playtime grows.
- [unit] A Steam game in a bottle launches through the bottle's Steam (`steam.exe -silent -applaunch <appid>`); a game added by hand launches its exe directly.
- [self] When the bottle's Steam is signed out, the game page says "Sign in to Steam in the bottle Steam to play this game." with "Open Steam".
- [unit] Running and playtime follow the game's own process (found by its exe), since the launch command exits at once.
- [live] Vernal Edge launches from the CrossOver Steam bottle on this Mac.
UX:
- Flow: double-click, Return, the game page's "Play" button or Game › Play (⌘P) → the cover shows "Starting…" → "Running" with the time → the game quits → playtime updates; Game › Stop (⌘.) asks first since unsaved progress may be lost
- Surface: inline state on the cover and the game page; "Running" section at the top of the sidebar while a game runs; confirmation dialog for Stop
- States: starting past half a second "Starting…"; error inline on the game page "Hollow Knight didn't start. CrossOver isn't installed." with "Show Details" (the log, later S-024); quits in under 10 seconds: "Hollow Knight quit right away" with "Show Details"
- Words: "Play" / « Jouer », "Stop" / « Arrêter », dialog "Stop Hollow Knight?" with "Unsaved progress in the game will be lost." and "Stop" / "Cancel", "Running" / « En cours », "Played 3 h 20 min" / « Joué 3 h 20 min »
- Access: Return and ⌘P launch; VoiceOver announces "Hollow Knight is running"
Status: done

### S-007 The game page
As the user, I select a game and see its page: cover, source, runner, path, playtime, last played, and buttons to launch, show in Finder and open its store page.
Screens: game-page
Depends: S-006
Acceptance:
- [snap] The game page for a Mac game and for a bottle game, in English and French.
UX:
- Flow: select a game → its page shows beside the grid (or Space shows it, Escape returns) → "Play", "Show in Finder", "Open Store Page"
- Surface: game page in the detail column (details of the selection while working)
- States: no selection: "Select a game to see its details"; missing files: inline "The game's files aren't at this location anymore." with "Locate…" and "Remove from Library"; long paths truncate in the middle with the full path in a tooltip
- Words: "Play" / « Jouer », "Show in Finder" / « Afficher dans le Finder », "Open Store Page" / « Ouvrir la page du magasin », labels "Source", "Runner" / « Lanceur », "Playtime" / « Temps de jeu », "Last played" / « Dernière partie »
- Access: Tab moves through the buttons in order; labels and values read as pairs
Status: done

### S-008 Search, sort and collections
As the user, I find a game by typing part of its name (words in any order, initials like "bg3"), sort by name, recently played or playtime, and put games in my own collections.
Screens: library
Depends: S-001
Acceptance:
- [unit] "bg3" finds Baldur's Gate 3; "knight hollow" finds Hollow Knight.
- [self] A new collection shows in the sidebar; a game can be in several.
UX:
- Flow: ⌘F or type in the toolbar search → the grid filters as I type → Escape clears; View › Sort By; File › New Collection (⌘⇧N) → name inline in the sidebar → Return; drag games onto a collection, or context menu "Add to Collection"
- Surface: toolbar search field; sort in the View menu and a toolbar menu; collections as sidebar pages, named inline
- States: no match "No games match "xyz"" with "Clear Search"; empty collection "Drag games here to add them"; ⌘Z undoes add, remove and delete
- Words: "Search Games" placeholder / « Rechercher des jeux », "Sort By" › "Name", "Recently Played", "Playtime" / « Trier par » › « Nom », « Joués récemment », « Temps de jeu », "New Collection" / « Nouvelle collection », "Add to Collection" / « Ajouter à la collection », "Delete Collection" / « Supprimer la collection » (games stay in the library)
- Access: ⌘F focuses search; collections reachable with the keyboard in the sidebar; drag has a menu equivalent
Status: done


### S-030 Cover art from the Steam store and SteamGridDB
As the user, I see a cover for every Steam game, newer games included, and for Windows games that aren't on Steam, using the same art sources as Attic.
Screens: library, settings-library
Depends: S-005
Acceptance:
- [unit] A Steam game's cover comes from the store's asset list (IStoreBrowseService/GetItems), whose newer file names can't be guessed; downloaded once and cached.
- [unit] With a SteamGridDB API key, a Steam game the store has no portrait art for gets SteamGridDB's best cover, and a Windows game that isn't on Steam is found by its name.
- [self] The key is kept in the Keychain (in memory in a test run), and clearing it forgets it.
UX:
- Flow: Settings › Library › Cover Art → paste the key → covers fill in without a restart
- Surface: a section in Settings › Library, with a link to make the key
- States: no key: the store's art and generated covers only; a wrong key or offline: the generated cover stays, nothing to read
- Words: "Cover Art" / « Couvertures », "SteamGridDB API Key" / « Clé d’API SteamGridDB », "Get a free key on steamgriddb.com" / « Obtenir une clé gratuite sur steamgriddb.com »
- Access: the key field is a secure field with its label read
Status: done

## M2 Tune Windows games (0.2.0)

### S-009 See the runners on this Mac
As the user, I open Runners in the sidebar and see CrossOver (version, bottles), Wine and Game Porting Toolkit builds, and MacRunner when they are installed.
Screens: runners
Depends: S-002
Acceptance:
- [unit] Finds CrossOver.app and its version, Gcenx Wine builds, and MacRunner.app.
- [snap] The Runners page with and without CrossOver.
UX:
- Flow: sidebar › Runners → the runners found at the last scan, CrossOver first with its bottles → Refresh scans again; the folder button shows a runner in the Finder
- Surface: sidebar page "Runners" (a place people come back to), a grouped form
- States: no CrossOver "CrossOver isn't installed. Hangar needs it to play the Windows games in your bottles." with "Get CrossOver"; no Wine build "None installed…" with "Get Wine builds for the Mac"; long paths truncate in the middle with the full path in a tooltip
- Words: "Runners" / « Lanceurs », "Bottles" / « Bouteilles », "Version 26.3", "Get CrossOver" / « Obtenir CrossOver », tooltip "Show CrossOver in the Finder" / « Afficher CrossOver dans le Finder »
- Access: runner name and version read as a pair; the Finder button has a label
Status: done

### S-010 Change a Windows game's graphics settings
As the user, I change a bottle game's graphics backend (Auto, D3DMetal, DXMT, DXVK, Wine), MSync, High Resolution Mode, MetalFX and AVX for Rosetta on its page.
Screens: game-page-settings
Depends: S-007
Acceptance:
- [unit] Each setting reads and writes the matching key in `cxbottle.conf` [EnvironmentVariables] and leaves the rest of the file byte for byte. (High Resolution Mode is Wine's `RetinaMode` in the bottle's `user.reg`, written the same way.)
- [self] Changing a setting writes it, and the game page shows the new value after a reload.
- [live] A copied bottle launched after the change uses the chosen backend (Metal HUD names it). Not run yet: needs a person at the Mac.
UX:
- Flow: select a game → game page › Settings → change Graphics or a switch → written to the bottle at once, the tab reads it back; a game in the bottle running: the section is dimmed with "Quit the games in this bottle to change its settings."
- Surface: the game page's Settings tab in the inspector (details of the selection), a segmented "Overview | Settings" at its top
- States: a Mac game: no bottle section; a bottle Hangar can't write: the error goes to the log and the value snaps back
- Words: "Graphics" / « Graphismes » with Auto, D3DMetal, DXMT, DXVK, Wine; "MSync"; "High Resolution Mode" / « Mode haute résolution »; "MetalFX"; "AVX for Rosetta" / « AVX pour Rosetta »; section "Bottle Steam" with the footer "These settings change the bottle Steam, for every game in it."
- Access: each switch has a tooltip that says what it does; labels and values read as pairs
Status: done

### S-011 Give a game its own bottle
As the user, when I change settings for a game whose bottle holds other games, Hangar warns me and offers to copy the bottle for this game alone.
Screens: game-page-settings
Depends: S-010
Acceptance:
- [self] The warning names the other games in the bottle; Copy makes a new bottle and moves the game to it.
- [unit] The copy gets a new BottleID and keeps the original untouched.
UX:
- Flow: game page › Settings → the bottle section warns "Kynseed and Bloodstained also run in this bottle. These settings change them too." → "Give Vernal Edge Its Own Bottle…" → confirmation → "Copying the bottle…" → the game moves to "Steam – Vernal Edge" and stays selected; the others stay in Steam
- Surface: an inline warning in the bottle section (information goes inline); a confirmation dialog for the copy, since it makes a new bottle on disk
- States: copying "Copying the bottle…" with a small spinner; error inline on the game page "Hangar couldn't copy the bottle. …"; the other games found in the copy go to Settings › Removed Games
- Words: "Give Vernal Edge Its Own Bottle…" / « Donner sa propre bouteille à Vernal Edge… », dialog "Give Vernal Edge its own bottle?" with "Copy Bottle" / « Copier la bouteille » and "Cancel"
- Access: the warning is a label with an icon and words, never color alone
Status: done

### S-012 Metal HUD for any game
As the user, I turn on the Metal performance HUD for a game, native or Windows, and see it the next time the game starts.
Screens: game-page-settings
Depends: S-006
Acceptance:
- [unit] Launch adds `MTL_HUD_ENABLED=1` to the game's environment when it's on.
- [manual] The HUD shows in a native Metal game and in a D3DMetal game. Not run yet: needs a person at the Mac.
UX:
- Flow: game page › Settings → "Metal Performance HUD" on → the next Play adds MTL_HUD_ENABLED=1 → the HUD shows in the game's top corner; off again the same way
- Surface: a switch on the Settings tab (changes one value on screen), kept with the game in the library
- States: a Steam game on the Mac: the footer says Hangar opens the game itself, since Steam can't pass the HUD on
- Words: "Metal Performance HUD" / « HUD de performances Metal », tooltip "Show frame rate, GPU time and memory over the game", footer "Shows the next time the game starts."
- Access: a standard switch with its label
Status: done

### S-013 Launch options
As the user, I set a game's exe, launch arguments and extra environment variables.
Screens: game-page-settings
Depends: S-006
Acceptance:
- [unit] Arguments with spaces and quotes reach the game as typed.
- [self] A variable set here reaches the launched process.
UX:
- Flow: game page › Settings › Launch Options → type arguments, or "Add Variable" → NAME = value → kept as typed, used at the next Play; a Windows program: "Choose…" picks another exe in the bottle, "Reset" goes back
- Surface: a section of the Settings tab; fields edited in place
- States: no options: an empty Arguments field with a sample prompt; a Steam game on the Mac with options: the footer says Hangar opens the game itself; a shortcut shows "Moonlit Harbor.lnk (shortcut)"
- Words: "Launch Options" / « Options de lancement », "Program" / « Programme », "Arguments", "Add Variable" / « Ajouter une variable », tooltip "Words passed to the game when it starts. Quote a word with spaces."
- Access: Tab moves name → value → remove; the remove button reads "Remove Variable"
Status: done

### S-014 Run through Wine or Game Porting Toolkit
As the user, I pick a Wine or Game Porting Toolkit build as a game's runner and Hangar runs it in its own prefix.
Screens: game-page-settings, runners
Depends: S-009
Acceptance:
- [unit] The launch command and environment for a Gcenx build and a GPTK build.
- [live] A small DX11 game runs through the GPTK build on this Mac. Not run: Game Porting Toolkit isn't installed on this Mac.
UX:
- Flow: game page › Settings › Runner → pick "Wine Stable 10.0" or "Game Porting Toolkit 3.0" → the next Play runs the game's files from the bottle in Hangar's own prefix (Application Support/Hangar/Prefixes); "CrossOver, bottle Classics" goes back
- Surface: a picker at the top of the Settings tab; the bottle section hides while another runner is chosen, since it doesn't apply
- States: no Wine build: only CrossOver, with "Install a Wine build or Game Porting Toolkit to run this game outside CrossOver."; the chosen runner removed: "Not installed anymore", and Play says "Its runner isn't installed anymore."; Steam games in a bottle keep CrossOver (they need the bottle's Steam)
- Words: "Runner" / « Lanceur », "CrossOver, bottle Classics", footer "Runs in a prefix of its own, from the game's files in the bottle Classics. The bottle's settings don't apply."
- Access: a standard picker with its label; the Overview's Runner row names the chosen runner
Status: done


## M3 Recipes (0.3.0)

### S-015 See whether a game runs on a Mac
As the user, I see on a game's page how well it runs for each method (native, Rosetta 2, CrossOver, Wine, Parallels), with the notes and a link to AppleGamingWiki.
Screens: game-page
Depends: S-007
Acceptance:
- [unit] Parses the `Compatibility/macOS` template from a page's source, status and notes for each method.
- [unit] The cached data is used offline and refreshed at most once a week.
- [snap] A game page with the status for each method, credited to AppleGamingWiki.
UX:
- Flow: select a game → its page asks AppleGamingWiki (or the cache, at most a week old) by title → "Runs on a Mac" lists each method with its verdict and notes → "From AppleGamingWiki" opens the page
- Surface: a section of the game page's Overview, under the cover and buttons
- States: loading "Checking AppleGamingWiki…" only past half a second; no page "AppleGamingWiki has no page for this game yet." with "Search AppleGamingWiki"; offline: the cache, however old, or nothing; long notes cut at three lines with the full text in a tooltip
- Words: "Runs on a Mac" / « Fonctionne sur Mac », verdicts "Perfect", "Playable", "Runs", "Doesn't run", "Not tested" / « Parfait », « Jouable », « Démarre », « Ne fonctionne pas », « Non testé »; methods Native, Rosetta 2, CrossOver, Wine, Parallels
- Access: a verdict is a word with a symbol, never color alone; method and verdict read as a pair
Status: done

### S-016 Apply a recipe
As the user, a game with a recipe shows "Recommended setup"; I see what it will change, apply it, and can undo it.
Screens: game-page, recipe-preview
Depends: S-010, S-017
Acceptance:
- [unit] A recipe's env vars, backend, DLL copies, registry keys, DLL overrides and launch args turn into a list of changes.
- [self] Applying the sample recipe changes the bottle; Undo puts every file back.
- [unit] The manifest is checked against its schema; a bad entry is skipped, not fatal.
UX:
- Flow: a CrossOver game with a recipe shows "Recommended Setup" on its Overview (notes, "Tested with CrossOver 26.3") → "Review Changes…" → sheet lists every change in plain words → "Apply Setup" saves a snapshot, writes the bottle and the launch options → the section reads "Applied" with "Undo", which puts every file back
- Surface: a section of the game page; a sheet "Apply the Recommended Setup to Moonlit Harbor?" (one short task that finishes or cancels)
- States: no recipe: no section; a shared bottle: the warning names the other games; a game in the bottle running, or a file the recipe needs missing: the reason in red with the fix, "Apply Setup" dimmed; a bad manifest entry: skipped and named on the Log page
- Words: "Recommended Setup" / « Configuration recommandée », "Review Changes…" / « Voir les changements… », "Apply Setup" / « Appliquer la configuration », "Undo" / « Annuler »; changes as "Turn on MSync", "Load dinput8.dll as native,builtin"
- Access: Return applies, Escape cancels; the error has a symbol, not color alone
Status: done

### S-017 Snapshot before every change, and roll back
As the user, Hangar saves a game's settings and bottle files before any change, and when a game breaks I pick an earlier snapshot ("worked on 12 Nov") and restore it.
Screens: game-page, snapshots
Depends: S-010
Acceptance:
- [unit] A snapshot holds `cxbottle.conf`, the registry files and the files a recipe touched; restore makes them byte for byte.
- [self] Change, break, restore: the sample game's settings come back.
- [self] Marking a launch "worked" labels that snapshot.
UX:
- Flow: Hangar saves a snapshot before every settings change, recipe and launch (skipped when nothing changed since the last one) → after a session of a minute or more the game page asks "Did Vernal Edge run well?" with "It Worked" / "Not Now" → "It Worked" labels the launch's snapshot "Worked on 12 Nov" → later, Settings › Snapshots › "Show Snapshots…" → pick one → "Restore…" → confirmation → files and options come back; the current ones are saved first
- Surface: inline question on the game page (information inline); a sheet "Snapshots of Vernal Edge" (one short task that finishes or cancels); a confirmation dialog, since restore overwrites files
- States: none yet "No Snapshots Yet" with what makes the first one; a game in the bottle running: Restore… is dimmed; 20 snapshots kept per game plus every working one
- Words: "Snapshot" / « Instantané », "It Worked" / « Ça a fonctionné », "Worked on 12 Nov" / « A fonctionné le 12 nov. », reasons "Before playing", "Before changing settings", "Before applying …", "Before restoring an earlier snapshot"
- Access: Return restores the selected snapshot, Escape closes; a working snapshot has a symbol and words, not color alone
Status: done

### S-018 Warn after a runner update
As the user, when CrossOver or a Wine build updates, Hangar tells me which games were last known to work on the old version, and offers their snapshots.
Screens: library
Depends: S-017
Acceptance:
- [unit] A version change in a runner is noticed at launch.
- [self] The notice lists the games that last worked on the old version.
UX:
- Flow: Hangar starts or refreshes → a runner's version differs from the one seen last → when games last worked on the old version, All Games shows "CrossOver updated from 26.2 to 26.3" with each game, the date it worked and "Show Snapshots…" → the Snapshots sheet for that game → "Dismiss" hides the notice
- Surface: a card above the All Games grid (information inline, not an alert: nothing is broken yet)
- States: first look at a runner: no notice; an update with no working games: no notice, a line in the Log; several runners updated: one card each
- Words: "CrossOver updated from 26.2 to 26.3" / « CrossOver est passé de 26.2 à 26.3 », "Show Snapshots…" / « Afficher les instantanés… », "Dismiss" / « Masquer »
- Access: the symbol is decoration; the title says it all
Status: done

### S-019 Share a recipe
As the user, when a game works, I send its setup as a recipe: Hangar copies the recipe JSON and opens a pre-filled issue on Hangar's GitHub.
Screens: game-page
Depends: S-016
Acceptance:
- [unit] The exported recipe holds only settings, never paths with my user name.
- [self] Share opens the issue page with the JSON in the body.
UX:
- Flow: game page › Settings › "Share This Setup…" → confirmation "Share the setup of Kynseed?" → "Copy and Open GitHub" copies the recipe JSON and opens a new issue on matguitarist/Hangar titled "Recipe: Kynseed" with the JSON in its body → the person checks it and submits it there, or closes the tab
- Surface: a button at the end of the Settings tab; a confirmation dialog, since it opens the browser and the page goes public once submitted
- States: a Mac game: no button (recipes are for bottles); a path or the user name in a variable or an argument: left out of the recipe
- Words: "Share This Setup…" / « Partager cette configuration… », "Copy and Open GitHub" / « Copier et ouvrir GitHub »; footer "never your files or your user name"
- Access: Return confirms, Escape cancels
Status: done

### S-020 Links for each game
As the user, I open a game's pages on AppleGamingWiki, PCGamingWiki, CodeWeavers, ProtonDB and its store from its page.
Screens: game-page
Depends: S-007
Acceptance:
- [unit] Links are built from the store id or the title.
UX:
- Flow: game page › Overview › "On the Web" (last section) → click a site → its page opens in the browser: the game's own page from the Steam id (or the AppleGamingWiki page Hangar found), else a search by title
- Surface: a section at the end of the Overview (links are information, not actions that change anything)
- States: no Steam id: four searches, no store row; a search shows a magnifying glass, a page an arrow out
- Words: site names as they are ("AppleGamingWiki", "PCGamingWiki", "CodeWeavers", "ProtonDB", "Steam"); "On the Web" / « Sur le Web »; tooltip "Open the page of Hollow Knight on ProtonDB" / « Ouvrir la page de Hollow Knight sur ProtonDB »
- Access: each row is one button; VoiceOver adds "Opens the game's page" or "Searches by title"
Status: done


## M4 Saves and crashes (0.4.0)

### S-021 Know where a game saves
As the user, I see where a game keeps its saves and settings, from PCGamingWiki, inside its bottle when it's a Windows game.
Screens: game-page, saves
Depends: S-007
Acceptance:
- [unit] PCGamingWiki's save paths for Windows and Mac turn into real paths (`%USERPROFILE%` inside the bottle, `~/Library`).
- [self] Show in Finder opens the sample game's save folder.
UX:
- Flow: game page › Overview › "Saves" (after the game's details) → each row names Saves or Settings and the folder → "Show in Finder" opens it (the nearest folder that exists when the game hasn't saved yet)
- Surface: a section of the Overview, like "Runs on a Mac"; read from PCGamingWiki once a month and cached
- States: loading past half a second "Checking PCGamingWiki…"; no page "PCGamingWiki has no page for this game yet."; no paths "PCGamingWiki doesn't say where this game saves."; not saved yet "Not on this Mac yet"; registry keys are left out
- Words: "Saves" / « Sauvegardes », "Show in Finder" / « Afficher dans le Finder », "Not on this Mac yet" / « Pas encore sur ce Mac », "From PCGamingWiki" / « Selon PCGamingWiki »
- Access: each row is a label, its path, and one button; the full path is in the tooltip
Status: done

### S-022 Back up saves before each launch
As the user, Hangar copies a game's saves before it launches, keeps the last ten copies, and can keep them in iCloud Drive.
Screens: saves
Depends: S-021
Acceptance:
- [unit] Keeps ten copies and removes older ones; a copy is skipped when nothing changed.
- [self] Launching the sample game makes one backup.
UX:
- Flow: Play → Hangar copies the saves (a moment, before the game starts) → the Saves section shows "Last backup: today at 14:02" and "Backups…"; Settings › Library › Save Backups › "Keep save backups in iCloud Drive"
- Surface: inline under the save rows; one toggle in Settings
- States: nothing to back up (no saves yet): no line; unchanged since the last copy: no new copy; a copy that fails: logged, the game still starts
- Words: "Last backup: %@" / « Dernière sauvegarde : %@ », "Keep save backups in iCloud Drive" / « Garder les sauvegardes dans iCloud Drive », "Save Backups" / « Sauvegardes des parties »
- Access: the toggle has its label read; the line is plain text
Status: done

### S-023 Restore a save
As the user, I pick a backup and restore it; Hangar backs up the current saves first.
Screens: saves
Depends: S-022
Acceptance:
- [self] Restore puts the old save back and the current one shows as a new backup.
UX:
- Flow: Saves section › "Backups…" → a sheet lists backups newest first (date, size, files) → select one → "Restore" → confirmation "Restore the saves from 12 Nov at 20:14? Hangar backs up the current saves first." → done, the sheet shows the new backup on top
- Surface: a sheet (a list to choose from, then one action); a confirmation dialog because it replaces files
- States: no backups "No backups yet. Hangar makes one each time you play."; game running: Restore disabled with "Quit the game first"
- Words: "Backups…" / « Sauvegardes… », "Restore" / « Restaurer », "Show in Finder" / « Afficher dans le Finder »
- Access: the list is keyboard navigable; Return restores the selection after the confirmation
Status: done

### S-024 Why a game crashed
As the user, when a Windows game quits within a minute or with an error, Hangar shows a plain reason ("Missing Visual C++ 2022 runtime", "This game needs DXVK") and the fix, with the full Wine log in LogKit's viewer.
Screens: crash-readout
Depends: S-006
Acceptance:
- [unit] Known Wine log lines map to reasons: missing DLLs, missing runtimes, unsupported DirectX features, out of memory.
- [self] A sample crash log shows its reason and the fix button.
UX:
- Flow: a Windows game quits within a minute → the game page shows "Hollow Knight quit: Missing Visual C++ 2022 runtime" with the fix ("Install it in CrossOver" or "Use DXVK") and "Show Log" → the Wine log opens in the Log viewer
- Surface: the existing notice section at the top of the game page; the log opens in its own "Wine Log — Hollow Knight" window (LogKit's viewer), beside the game page
- States: no known reason "Hangar didn't find why. The Wine log may tell." with "Show Log"; a fix that changes settings takes a snapshot first (S-017)
- Words: "Show Log" / « Afficher le journal », reasons in plain words, no Wine jargon in the first line
- Access: the reason is the label's text; buttons have hover help
Status: done


### S-031 Game details from the web
As the user, I see what a game is about on its page: a short description, developer, publisher, release date and genres, from the Steam store for Steam games and from TheGamesDB (with my free API key) for the others, in French when the store has it.
Screens: game-page, settings-library
Depends: S-007, S-030
Acceptance:
- [unit] Steam's appdetails answer becomes details: plain-text description, developers, publishers, release date and genres, asked in the app's language.
- [unit] TheGamesDB's best match for a title on PC (or Mac for a Mac game), with genre, developer and publisher names from its lists, fetched at most once a month.
- [unit] Details are cached on disk, asked again at most once a month, and the cache answers offline.
- [self] The sample game's details show from the sample answers; the TheGamesDB key is kept in the Keychain (in memory in a test run), and clearing it forgets it.
UX:
- Flow: game page › Overview › "About" (under the header) → the description (four lines, "More" shows the rest) → Developer, Publisher, Released, Genres; Settings › Library › Game Details → paste the TheGamesDB key → details fill in without a restart
- Live: `HANGAR_LIVE_TGDB_KEY=<key> swift test --filter LiveDetails` checks the Steam store, TheGamesDB and PCGamingWiki for real
- Surface: a section of the Overview; one secure field and a link in Settings › Library
- States: loading: nothing (the section appears when details arrive); nothing found or offline with no cache: no section; no key: Steam games only
- Words: "About" / « À propos », "Developer" / « Développeur », "Publisher" / « Éditeur », "Released" / « Sortie », "Genres" / « Genres », "More" / « Plus », "Less" / « Moins », "From the Steam store" / « Selon le magasin Steam », "From TheGamesDB" / « Selon TheGamesDB », "Game Details" / « Détails des jeux », "TheGamesDB API Key" / « Clé d’API TheGamesDB », "Request a key on the TheGamesDB forums" / « Demander une clé sur les forums de TheGamesDB »
- Access: the description is selectable text; rows are label and value
Status: done

### S-032 Fetch every game's details at once
As the user, I fetch the details of my whole library in one go, see how far it got, stop it, and ask again for one game whose details are wrong or old.
Screens: library, game-page
Depends: S-031
Acceptance:
- [unit] Refresh asks the web again however fresh the cache is, and keeps the old details offline.
- [unit] Steam store requests are spaced out (one every 1.5 seconds), so a whole library isn't refused.
- [self] Fetch All Details goes through every game, shows its progress and the menu turns into Stop; Refresh Details asks again for one game.
UX:
- Flow: View › Fetch All Details (⌥⌘R) → a banner above the library: "Fetching game details… 4 of 10" with a progress bar and Stop → "Found details for 8 of 10 games" with a note and Dismiss; Game › Refresh Details, or right-click a game › Refresh Details
- Surface: a banner card above the grid, like runner updates; menu items
- States: running, stopped ("Stopped after 4 of 10 games"), finished; no TheGamesDB key: the note says games not on Steam need one
- Words: "Fetch All Details" / « Chercher tous les détails », "Stop Fetching Details" / « Arrêter la recherche des détails », "Refresh Details" / « Actualiser les détails », "Fetching game details… %lld of %lld" / « Recherche des détails des jeux… %lld sur %lld », "Found details for %lld of %lld games" / « Détails trouvés pour %lld jeux sur %lld »
- Access: the progress bar is read as "4 of 10 games"
Status: done

### S-033 A Mac version from the stores
As the user, I see that a game has a Mac version even when AppleGamingWiki doesn't say so, because Steam sells one or it's on the Mac App Store.
Screens: game-page
Depends: S-015, S-031
Acceptance:
- [unit] Steam's appdetails says whether there's a Mac version (platforms.mac).
- [unit] The Mac App Store search (Apple's public search, no key, the person's country) finds only an app of the same name, cached a month.
- [self] A game whose wiki page has no native verdict shows Steam's Mac version; a game with no wiki page on the Mac App Store shows it, and Open in the App Store opens its page.
UX:
- Flow: game page › Overview › Runs on a Mac → "Native — Mac version" first, with "Steam sells a Mac version of this game." and/or "On the Mac App Store. Open in the App Store"
- Live: `HANGAR_LIVE_TGDB_KEY=<key> swift test --filter Live` checks Blue Prince on Steam and the Mac App Store
- States: shown only when the wiki has no native verdict and a store has one; while the wiki loads: nothing
- Words: "Mac version" / « Version Mac », "Steam sells a Mac version of this game." / « Steam vend une version Mac de ce jeu. », "On the Mac App Store." / « Sur le Mac App Store. », "Open in the App Store" / « Ouvrir dans l’App Store »
- Access: the verdict is a word with a symbol, never color alone; hover help says how well it runs isn't rated
Status: done


## M5 Life on a Mac (0.5.0)

### S-025 Battery profiles
As the user, I set a game to use other settings on battery (Low Power Mode, a lower resolution, the HUD off) and Hangar applies them when the Mac is unplugged.
Screens: game-page-settings
Depends: S-010
Acceptance:
- [unit] The power source picks the profile at launch.
- [manual] On battery, the game launches with the battery profile.
- [self] On battery the plan uses the battery settings, the display is lowered and put back, and Low Power Mode is suggested when it's off.
UX:
- Flow: game page › Settings › On Battery → "Use other settings on battery" → Metal Performance HUD, Lower the display resolution, Suggest Low Power Mode (on by default) → Play while unplugged → the game starts with them; the display goes to the next "looks like" size down and back when the game quits; with Low Power Mode off, the Overview shows "Low Power Mode is off…" with Open Battery Settings and Not Now
- Surface: a section of the Settings tab (only on a Mac with a battery); a notice on the Overview, like "Did it run well?"
- States: off (one toggle, footer says what it's for); on (three toggles); no lower display mode: the resolution stays, nothing to say; Low Power Mode already on: no reminder
- Words: "On Battery" / « Sur batterie », "Use other settings on battery" / « Utiliser d’autres réglages sur batterie », "Lower the display resolution" / « Baisser la résolution de l’écran », "Suggest Low Power Mode" / « Suggérer le mode Économie d’énergie », "Open Battery Settings" / « Ouvrir les réglages Batterie »
- Honest: Hangar can't turn on Low Power Mode (that needs an administrator), so it suggests it; the resolution change is for Hangar's lifetime only, so macOS puts it back even if Hangar quits
- Access: every toggle has hover help; the notice is text with a symbol and two buttons
Status: done

### S-034 Suggested settings
As the user, I see which bottle settings the wikis recommend for a Windows game, with the reason for each, and apply them in one click that I can undo.
Screens: game-page
Depends: S-010, S-015, S-021
Acceptance:
- [unit] AppleGamingWiki's CrossOver notes become suggestions only from sentences that recommend (a sentence with "crash", "doesn't", "black"… is a warning); two different backends recommended means no graphics advice.
- [unit] PCGamingWiki's Direct3D version is a rule only when the notes say nothing: 10 → DXMT, 9 and older → DXVK; 11 and 12 nothing (CrossOver's Auto already picks D3DMetal).
- [unit] What's already set is never suggested.
- [self] The sample game's notes become suggestions; Apply changes the bottle after a snapshot; Undo puts it back.
UX:
- Flow: game page › Overview › Suggested Settings (above About) → each change with "AppleGamingWiki: “Runs with D3DMetal”" or "PCGamingWiki lists Direct3D 9; DXVK usually runs that best." → Apply Suggestions (snapshot first) → "Applied the suggested settings." with Undo; Not Now hides it for this session
- Surface: a section of the Overview, only for games in a CrossOver bottle with something to suggest
- States: nothing to suggest: no section; a game running in the bottle: Apply disabled with "Quit the games in this bottle first"
- Honest: "From the wikis, not tested on this Mac."; a Mac version comes only from the stores (PCGamingWiki's macOS flag said Bloodstained had one; its Mac version was cancelled)
- Words: "Suggested Settings" / « Réglages suggérés », "Apply Suggestions" / « Appliquer les suggestions », "Applied the suggested settings." / « Réglages suggérés appliqués. », "From the wikis, not tested on this Mac." / « Selon les wikis, pas encore essayé sur ce Mac. »
- Access: each suggestion is a label, a value and its reason in text; Apply has hover help
Status: done

### S-026 Quick launch from the menu bar
As the user, I click Hangar's menu bar icon and launch one of my recent games, or see what's running.
Screens: menu-bar
Depends: S-006
Acceptance:
- [snap] The menu with recent games and a running game.
- [unit] Recently played: the five played last, without the running ones.
UX:
- Flow: click the gamepad icon in the menu bar → a panel: Running (each with "Playing since 6:12 PM" and Stop…), Recently Played (five, "Played yesterday") → click a game to play it, a running one to bring it to the front, Stop… to confirm in the main window; Open Hangar; Quit Hangar
- Surface: a menu bar extra in window style (covers help recognize games); rows highlight under the pointer and with keyboard focus, like menu items; Settings › General › Menu Bar turns it off
- States: nothing played yet: "The games you play show here."; starting: "Starting…"; with the icon on, Hangar keeps running when its window closes
- Words: "Running" / « En cours », "Recently Played" / « Joués récemment », "Played %@" / « Joué %@ », "Playing since %@" / « En cours depuis %@ », "Open Hangar" / « Ouvrir Hangar », "Quit Hangar" / « Quitter Hangar », "Show Hangar in the menu bar" / « Afficher Hangar dans la barre des menus »
- Access: every row is a button with hover help; Tab moves through rows; ⌘Q quits
Status: done

### S-027 Shortcuts actions
As the user, I launch a game, or back up its saves, from Shortcuts and Spotlight.
Depends: S-006
Acceptance:
- [self] The "Launch Game" intent launches the sample game.
Status: todo


## M6 Couch mode (0.6.0)

### S-028 Couch mode
As the user, I open a full-screen view of cover art with large text that I can use from the sofa.
Screens: couch
Depends: S-005
Acceptance:
- [snap] Couch mode in light and dark.
Status: todo

### S-029 Play with a controller
As the user, I browse, launch and see game details with an Xbox, PlayStation or Switch controller; Hangar comes back to the front when the game quits.
Screens: couch
Depends: S-028
Acceptance:
- [self] Simulated controller input moves the selection and launches.
- [manual] A DualSense and an Xbox pad both work.
Status: todo


## Later

- Import Epic and GOG games installed by Heroic.
- Open a game in MacRunner (needs a URL scheme or CLI from MacRunner).
- Frame cap for D3DMetal and DXMT games (needs a test).
- HDR for Windows games (needs a test).
- Steam achievements read from `appcache/stats` (needs a probe).
- Game Mode for Windows games through a wrapper app (opt-in, needs a test).
- ReShade on the DXVK path.
- Parallels as a runner.

## Dropped

- Shipping our own Wine or translation layer: drive the runners people have.
- Bundling D3DMetal: its license forbids it in a paid app and it's not needed.
- Installing or buying games from stores: the stores and Heroic do that.
- Accounts, cloud sync of the library, sharing: local only.
- Anti-cheat and online games: they don't run under Wine.
