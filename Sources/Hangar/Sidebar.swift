import HangarKit
import SwiftUI

/// Running, the library, its sources, the person's collections, and the log.
struct Sidebar: View {
    @Environment(AppModel.self) private var model
    @State private var crossOverOpen = true

    var body: some View {
        @Bindable var model = model
        List(selection: $model.sidebar) {
            if !model.running.isEmpty {
                Section("Running") {
                    Label("Running", systemImage: "play.circle")
                        .badge(model.running.count)
                        .tag(SidebarItem.running)
                }
            }
            Section("Library") {
                Label("All Games", systemImage: "square.grid.2x2")
                    .badge(model.library.games.count)
                    .tag(SidebarItem.allGames)
            }
            Section("Sources") {
                if count(.steam) > 0 || model.steamNote != nil {
                    VStack(alignment: .leading, spacing: 2) {
                        Label(GameSource.steam.title, systemImage: GameSource.steam.symbol)
                        if let note = model.steamNote {
                            Text(note)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(6)
                                .padding(.leading, 28)
                                .help(note)
                        }
                    }
                    .badge(count(.steam))
                    .tag(SidebarItem.source(.steam))
                }
                if !model.bottles.isEmpty {
                    DisclosureGroup(isExpanded: $crossOverOpen) {
                        ForEach(model.bottles, id: \.self) { bottle in
                            VStack(alignment: .leading, spacing: 2) {
                                Label(bottle, systemImage: "shippingbox")
                                if let note = model.bottleNote(bottle) {
                                    Text(note)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(6)
                                        .padding(.leading, 28)
                                        .help(note)
                                }
                            }
                            .help(String(localized: "Bottle \(bottle)"))
                            .tag(SidebarItem.bottle(bottle))
                        }
                    } label: {
                        Label(GameSource.crossOver.title, systemImage: GameSource.crossOver.symbol)
                            .badge(count(.crossOver))
                            .tag(SidebarItem.source(.crossOver))
                    }
                }
                ForEach([GameSource.heroic, .macApp, .addedByHand], id: \.self) { source in
                    if count(source) > 0 {
                        Label(source.title, systemImage: source.symbol)
                            .badge(count(source))
                            .tag(SidebarItem.source(source))
                    }
                }
            }
            Section("Collections") {
                ForEach(model.library.collections) { collection in
                    CollectionRow(collection: collection)
                        .tag(SidebarItem.collection(collection.id))
                }
            }
            Section {
                Label("Runners", systemImage: "gearshape.2")
                    .badge(model.runners.count)
                    .tag(SidebarItem.runners)
                Label("Health", systemImage: "stethoscope")
                    .badge(model.healthIssues.count)
                    .tag(SidebarItem.health)
                Label("Storage", systemImage: "internaldrive")
                    .tag(SidebarItem.storage)
                Label("Log", systemImage: "doc.text.magnifyingglass")
                    .tag(SidebarItem.log)
            }
        }
        // The sidebar keeps each row's height from its first layout. A scan that adds a note
        // (a library on an unplugged drive) or bottles makes rows taller, so lay the list out again.
        .id(rowShape)
    }

    private var rowShape: [String] {
        [model.steamNote ?? ""] + model.bottles.map { $0 + (model.bottleNote($0) ?? "") }
    }

    private func count(_ source: GameSource) -> Int {
        model.library.games.filter { $0.source == source }.count
    }
}

/// A collection in the sidebar: named inline when new, a drop target for games.
private struct CollectionRow: View {
    @Environment(AppModel.self) private var model
    let collection: GameCollection
    @State private var name = ""
    @State private var targeted = false
    @FocusState private var focused: Bool

    var body: some View {
        Group {
            if model.renamingCollection == collection.id {
                TextField("Collection Name", text: $name)
                    .focused($focused)
                    .onSubmit { model.renameCollection(collection.id, to: name) }
                    .onExitCommand { model.renamingCollection = nil }
                    .onAppear { name = collection.name; focused = true }
                    .onChange(of: focused) { if !focused { model.renameCollection(collection.id, to: name) } }
            } else {
                Label(collection.name, systemImage: "rectangle.stack")
                    .badge(collection.gameIDs.count)
            }
        }
        .dropDestination(for: String.self) { ids, _ in
            model.addToCollection(ids, collection.id)
            return true
        } isTargeted: { targeted = $0 }
        .listRowBackground(targeted ? RoundedRectangle(cornerRadius: Radius.control).fill(Palette.accent.opacity(0.25)) : nil)
        .contextMenu {
            Button("Rename") { model.renamingCollection = collection.id }
            Button("Delete Collection") { model.deleteCollection(collection.id) }
        }
    }
}
