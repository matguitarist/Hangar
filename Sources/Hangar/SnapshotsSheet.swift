import HangarKit
import SwiftUI

/// A game's snapshots, newest first, to pick one and restore it.
struct SnapshotsSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let gameID: String
    @State private var selection: UUID?
    @State private var confirming: SettingsSnapshot?

    var body: some View {
        let game = model.game(gameID)
        let list = model.snapshotList(gameID)
        VStack(alignment: .leading, spacing: 0) {
            Text("Snapshots of \(game?.title ?? "")")
                .font(.headline)
                .padding([.horizontal, .top], Space.xl)
            Text("Hangar saves a game's settings and bottle files before every change and every launch.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, Space.xl)
                .padding(.top, Space.xs)
            Group {
                if list.isEmpty {
                    ContentUnavailableView("No Snapshots Yet", systemImage: "clock.arrow.circlepath",
                                           description: Text("The first one is saved the next time you change a setting or play."))
                } else {
                    List(list, selection: $selection) { snapshot in
                        SnapshotRow(snapshot: snapshot).tag(snapshot.id)
                    }
                    .listStyle(.bordered)
                    .alternatingRowBackgrounds()
                }
            }
            // As tall as its rows, up to a point: no empty stripes under a short list.
            .frame(height: list.isEmpty ? 200 : min(280, CGFloat(list.count) * 54 + 4))
            .padding(Space.xl)
            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Restore…") { confirming = list.first { $0.id == selection } }
                    .keyboardShortcut(.defaultAction)
                    .disabled(selection == nil || game.flatMap(\.bottle).map(model.bottleIsBusy) == true)
            }
            .padding([.horizontal, .bottom], Space.xl)
        }
        .frame(width: 480)
        .noInitialFocus()
        .onAppear { selection = list.first(where: { $0.worked != nil })?.id ?? list.first?.id }
        .confirmationDialog(String(localized: "Restore the snapshot from \(confirming?.date.formatted(date: .abbreviated, time: .shortened) ?? "")?"),
                            isPresented: Binding(get: { confirming != nil }, set: { if !$0 { confirming = nil } })) {
            Button("Restore") {
                if let snapshot = confirming { model.restore(snapshot) }
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("\(game?.title ?? "")'s settings and bottle files go back to how they were. Hangar saves the current ones first, so you can come back.")
        }
    }
}

private struct SnapshotRow: View {
    let snapshot: SettingsSnapshot

    var body: some View {
        HStack(spacing: Space.md) {
            Image(systemName: snapshot.worked == nil ? "clock" : "checkmark.seal.fill")
                .foregroundStyle(snapshot.worked == nil ? AnyShapeStyle(.secondary) : AnyShapeStyle(Palette.accent))
                .frame(width: 20)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(snapshot.title)
                Text([snapshot.reasonText, snapshot.runner].compactMap { $0 }.joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}
