import HangarKit
import SwiftUI

/// Add Windows Game: an .exe needs the bottle it runs in.
struct AddGameSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let request: AddRequest
    @State private var bottle = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Add Windows Game")
                .font(.headline)
                .padding([.horizontal, .top], Space.margin)
            form
            HStack(spacing: Space.sm) {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Add") {
                    model.addWindowsGame(request.file, bottle: bottle)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!request.isWindowsProgram || bottle.isEmpty)
            }
            .padding([.horizontal, .bottom], Space.margin)
        }
        .frame(width: 480)
        .noInitialFocus()
        .fitsContent()
        .gridArea("add-game")
        .onAppear { bottle = defaultBottle }
    }

    private var form: some View {
        Form {
            Section {
                Picker("Bottle:", selection: $bottle) {
                    ForEach(model.bottles, id: \.self) { Text($0).tag($0) }
                }
                .disabled(model.bottles.isEmpty)
                LabeledContent("File:") {
                    Text(request.file.lastPathComponent)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .help(request.file.path)
                }
            } footer: {
                if !request.isWindowsProgram {
                    Label("This file isn't a Windows program.", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.secondary)
                } else if model.bottles.isEmpty {
                    Label("CrossOver has no bottles. Make one in CrossOver first.", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.columns)
        .padding(Space.margin)
    }

    /// The bottle the file sits in, or the first one.
    private var defaultBottle: String {
        let path = request.file.path
        return model.bottles.first { path.hasPrefix(model.roots.bottles.appending(path: $0).path + "/") } ?? model.bottles.first ?? ""
    }
}
