import Charts
import HangarKit
import SwiftUI

/// Storage (S-039): what Hangar's games, bottles, prefixes and copies take on disk, largest first.
struct StoragePage: View {
    @Environment(AppModel.self) private var model
    @State private var trashing: StorageItem?
    @State private var deleting: StorageItem.Kind?

    var body: some View {
        Form {
            if let items = model.storageItems {
                let totals = StorageScanner.totals(items)
                Section {
                    Chart(StorageItem.Kind.allCases.filter { (totals[$0] ?? 0) > 0 }, id: \.self) { kind in
                        BarMark(x: .value("Size", totals[kind] ?? 0))
                            .foregroundStyle(by: .value("Kind", kind.title))
                    }
                    .chartXAxis(.hidden)
                    .chartLegend(position: .bottom, alignment: .leading)
                    .frame(height: 64)
                    .accessibilityHidden(true)
                    ForEach(StorageItem.Kind.allCases.filter { (totals[$0] ?? 0) > 0 }, id: \.self) { kind in
                        LabeledContent(kind.title, value: Self.size(totals[kind] ?? 0))
                    }
                } header: {
                    Text("On Disk")
                }
                ForEach(StorageItem.Kind.allCases, id: \.self) { kind in
                    let list = items.filter { $0.kind == kind }
                    if !list.isEmpty {
                        Section(kind.title) {
                            ForEach(list) { row($0) }
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Storage")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                if model.measuringStorage {
                    HStack(spacing: Space.sm) {
                        ProgressView().controlSize(.small)
                        Text("Measuring…").foregroundStyle(.secondary)
                    }
                }
                Button { Task { await model.measureStorage() } } label: { Label("Measure Again", systemImage: "arrow.clockwise") }
                    .help(String(localized: "Measure again"))
                    .disabled(model.measuringStorage)
            }
        }
        .task { await model.measureStorage() }
        .confirmationDialog(String(localized: "Move \(trashing?.name ?? "") to the Trash?"), isPresented: Binding(get: { trashing != nil }, set: { if !$0 { trashing = nil } })) {
            Button("Move to Trash", role: .destructive) { if let item = trashing { Task { await model.trashPrefix(item) } } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("No game in the library runs in this prefix anymore.")
        }
        .confirmationDialog(deleting == .snapshots ? String(localized: "Delete old snapshots?") : String(localized: "Delete old save backups?"),
                            isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
            Button("Delete", role: .destructive) {
                Task { if deleting == .snapshots { await model.deleteOldSnapshots() } else { await model.deleteOldBackups() } }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(deleting == .snapshots ? String(localized: "Each game keeps its three newest snapshots and the ones that worked.")
                                        : String(localized: "Each game keeps its three newest save backups."))
        }
    }

    @ViewBuilder
    private func row(_ item: StorageItem) -> some View {
        LabeledContent {
            HStack(spacing: Space.sm) {
                Text(Self.size(item.bytes)).monospacedDigit().foregroundStyle(.secondary)
                switch item.kind {
                case .prefixes where item.unused:
                    Button("Move to Trash…") { trashing = item }
                case .snapshots:
                    Button("Delete Old Snapshots…") { deleting = .snapshots }
                case .saveBackups:
                    Button("Delete Old Backups…") { deleting = .saveBackups }
                default:
                    EmptyView()
                }
                Button { model.showStorageItem(item) } label: { Image(systemName: "folder") }
                    .buttonStyle(.borderless)
                    .help(String(localized: "Show in Finder"))
                    .accessibilityLabel(Text("Show in Finder"))
            }
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name).lineLimit(1).truncationMode(.middle)
                if item.unused {
                    Text("Unused").font(.caption).foregroundStyle(.secondary)
                }
            }
            .help(item.path)
        }
    }

    static func size(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
