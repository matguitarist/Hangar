# Hangar

A native macOS app in SwiftUI that puts every game on an Apple Silicon Mac in
one library: native Mac games, and Windows games run through CrossOver and other
runners, with per-game recipes, settings snapshots, save backups, and crash
readouts. Free and open source (GPL-3). `docs/BRIEF.md` says what it is,
`docs/STORIES.md` what is built and what comes next, `docs/GLOSSARY.md` the
words it uses, and `docs/research/game-managers.md` why.

Shared rules for my Mac apps (build and check, design rules, skills, git):
@~/.claude/mac-app-conventions.md

Shared rules for how every project is laid out and named:
@~/.claude/project-layout.md

## Layout

- `Sources/Hangar/` the app. `App.swift` has the window, menus, and the database location.
- `Sources/HangarKit/` rules and data logic with no SwiftUI. Tests in `Tests/HangarKitTests/`.
- `Package.swift` a Swift package. There is no Xcode project.
- `build.sh` builds, signs, and installs `~/Applications/Hangar.app`.
- Release: `tools/release.sh <version>` (settings in `release.conf`, version in `Info.plist.in`). Use the mac-release skill.
- `Icon/AppIcon.icon` the app icon, an Icon Composer file (JSON plus SVG layers). `build.sh` compiles it with `tools/make_icon.sh`; `tools/icon_review.sh` renders every look into one PNG.
- `docs/` the brief, the stories, the glossary, and the research. The roadmap is "Hangar Roadmap" in Thimble.
- `Localization/Localizable.xcstrings` English and French. HangarKit's visible words use `String(localized:bundle: .main)`, so they live in the same catalog.

## Checks specific to this app

- `APP_SNAPSHOT_MIN=1 tools/snap.sh` shoots the window at its smallest size.
- `APP_STORE` must be a file in /tmp: tests, snapshots, and the self-test never read the real library in `~/Library/Application Support/Hangar/`, never change a real bottle, and never launch a real game. Probes against this Mac's bottles work on a copy of the bottle.