# Architecture review, 2026-11-24 (end of M6)

M6 added couch mode and controllers. The parts with logic live in HangarKit with tests: `CouchNavigator` (rows and selection), `GamepadMapper` (dead zone, presses, repeat) and `SteamAchievements` with `BinaryKeyValues`. The app side is `AppModel+Couch` (one `couch(_:)` entry for keys, buttons and the self-test), `Controllers.swift` (GameController polled at 60 Hz only while a pad is connected and Hangar is active), `CouchView` and `CouchHints`.

## Couch state off the main model  [Worth exploring]
`AppModel` gained four couch properties; couch mode reads the library and launches through the model, so a separate `CouchModel` would only forward. Split it if couch mode grows its own pages (collections, settings).

## Polling the controller  [Considered, not recommended]
`valueChangedHandler` would avoid the timer, but key repeat needs a clock anyway, and the poll stops when no pad is connected.

## A runner protocol  [Worth exploring]
Unchanged from M5.
