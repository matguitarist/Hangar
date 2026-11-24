import HangarKit
import SwiftUI

/// A game's save backups, newest first, to pick one and restore it (S-023).
struct BackupsSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let gameID: String
    @State private var selection: String?
    @State private var confirming: SaveBackup?

    var body: some View {
        let game = model.game(gameID)
        let list = model.backupList(gameID)
        let isRunning = model.running[gameID] != nil
        VStack(alignment: .leading, spacing: 0) {
            Text("Save Backups of \(game?.title ?? "")")
                .font(.headline)
                .padding([.horizontal, .top], Space.xl)
            Text("Hangar copies the saves each time you play, and keeps the last ten copies.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, Space.xl)
                .padding(.top, Space.xs)
            Group {
                if list.isEmpty {
                    ContentUnavailableView("No Backups Yet", systemImage: "externaldrive.badge.timemachine",
                                           description: Text("Hangar makes one each time you play."))
                } else {
                    List(list, selection: $selection) { backup in
                        BackupRow(backup: backup).tag(backup.id)
                    }
                    .listStyle(.bordered)
                    .alternatingRowBackgrounds()
                }
            }
            .frame(height: list.isEmpty ? 200 : min(280, CGFloat(list.count) * 54 + 4))
            .padding(Space.xl)
            HStack {
                Button("Show in Finder") {
                    if let backup = list.first(where: { $0.id == selection }) { model.showBackup(backup, gameID: gameID) }
                }
                .disabled(selection == nil)
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Restore…") { confirming = list.first { $0.id == selection } }
                    .keyboardShortcut(.defaultAction)
                    .disabled(selection == nil || isRunning)
                    .help(isRunning ? String(localized: "Quit the game first") : String(localized: "Put these saves back"))
            }
            .padding([.horizontal, .bottom], Space.xl)
        }
        .frame(width: 480)
        .noInitialFocus()
        .onAppear { selection = list.first?.id }
        .confirmationDialog(String(localized: "Restore the saves from \(confirming?.date.formatted(date: .abbreviated, time: .shortened) ?? "")?"),
                            isPresented: Binding(get: { confirming != nil }, set: { if !$0 { confirming = nil } })) {
            Button("Restore") {
                if let backup = confirming {
                    Task { await model.restoreBackup(backup, gameID: gameID); selection = model.backupList(gameID).first?.id }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Hangar backs up the current saves first, so you can come back to them.")
        }
    }
}

private struct BackupRow: View {
    let backup: SaveBackup

    var body: some View {
        HStack(spacing: Space.md) {
            Image(systemName: backup.reason == .beforeRestore ? "arrow.uturn.backward.circle" : "clock")
                .foregroundStyle(.secondary)
                .frame(width: 20)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(backup.date.formatted(date: .abbreviated, time: .shortened))
                Text([reason, files, ByteCountFormatter.string(fromByteCount: backup.bytes, countStyle: .file)].joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }

    private var reason: String {
        switch backup.reason {
        case .launch: String(localized: "Before playing")
        case .beforeRestore: String(localized: "Before a restore")
        case .byHand: String(localized: "Backed up by you")
        }
    }

    private var files: String {
        backup.files == 1 ? String(localized: "1 file") : String(localized: "\(backup.files) files")
    }
}
