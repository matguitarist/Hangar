# Architecture review, 2026-11-23 (end of M1)

Survey: 3,000 lines. The biggest files are `HangarKit/Scanner.swift` (316), `Hangar/AppModel+Actions.swift` (306) and `Hangar/AppModel.swift` (278). No file is near 600 lines. HangarKit holds parsing, scanning, merging, search, launch plans, process matching and covers, with 21 unit tests on the sample library in `Tests/Fixtures`.

## Launch tracking rules in HangarKit  [Strong] (done)
The steps of a launched game (starting, running, finished, "quit right away" under 10 seconds, the 30 s and 120 s start timeouts) lived in the main-actor `AppModel`, where only the self-test could reach them. They are now `LaunchTracker` and `LaunchState` in HangarKit, a pure step function over the process list, with three unit tests. The model only runs the monitor loop and applies the events. M2's crash readout and M3's snapshots before launch build on this seam.

## Split the library store from the window state  [Worth exploring]
`AppModel` holds the saved library (games, collections, removed games, saving) and the window's state (sidebar, selection, search, sheets). Once recipes and snapshots arrive (M2, M3), a `LibraryStore` that owns `LibraryFile`, saving and undo would keep `AppModel` about the window. Do it when the first M2 story adds stored data.

## A runner protocol  [Speculative]
`LaunchPlanner` switches on `RunnerKind` (native, CrossOver). When Wine, Game Porting Toolkit or MacRunner join (the brief's runners), a `Runner` with one adapter per kind would keep each runner's paths and arguments in one place. Two runners don't justify it yet.
