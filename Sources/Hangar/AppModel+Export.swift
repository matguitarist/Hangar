import AppKit
import HangarKit
import SwiftUI
import UniformTypeIdentifiers

/// Export and import the library (S-046).
extension AppModel {
    func exportLibrary(to url: URL) {
        do {
            try LibraryExport(library: library).encoded().write(to: url, options: .atomic)
            log.post(.info, "Exported \(library.games.count) games to \(url.lastPathComponent)", source: "Library")
        } catch {
            log.post(.error, "Can't export the library: \(error.localizedDescription)", source: "Library")
        }
    }

    /// Merges a file into the library, with Undo.
    @discardableResult
    func importLibrary(from url: URL) -> ImportSummary? {
        let export: LibraryExport
        do {
            export = try LibraryExport.decode(Data(contentsOf: url))
        } catch {
            log.post(.error, "Can't read \(url.lastPathComponent) as a Hangar library: \(error.localizedDescription)", source: "Library")
            importMessage = String(localized: "\(url.lastPathComponent) isn't a Hangar library.")
            return nil
        }
        let before = library
        let summary = library.importing(export, coversFolder: Store.coversFolder)
        coverGeneration += 1
        undoManager?.registerUndo(withTarget: self) { model in model.library = before; model.importMessage = nil }
        undoManager?.setActionName(String(localized: "Import Library"))
        lastImportUndo = before
        importMessage = String(localized: "Imported \(summary.games) games and \(summary.collections) collections.")
        log.post(.info, "Imported \(summary.games) games and \(summary.collections) collections from \(url.lastPathComponent)", source: "Library")
        return summary
    }

    /// The import toast's Undo.
    func undoImport() {
        guard let before = lastImportUndo else { return }
        library = before
        lastImportUndo = nil
        importMessage = nil
        coverGeneration += 1
    }
}

extension GamePanels {
    static var libraryType: UTType { UTType(filenameExtension: LibraryExport.fileExtension, conformingTo: .json) ?? .json }

    static func exportLibrary(_ model: AppModel) {
        let panel = NSSavePanel()
        panel.title = String(localized: "Export Library")
        panel.nameFieldStringValue = String(localized: "Hangar Library") + "." + LibraryExport.fileExtension
        panel.allowedContentTypes = [libraryType]
        if panel.runModal() == .OK, let url = panel.url { model.exportLibrary(to: url) }
    }

    static func importLibrary(_ model: AppModel) {
        let panel = NSOpenPanel()
        panel.title = String(localized: "Import Library")
        panel.allowedContentTypes = [libraryType, .json]
        if panel.runModal() == .OK, let url = panel.url { model.importLibrary(from: url) }
    }
}

/// "Imported 42 games and 3 collections." with Undo, at the top of the window for a few seconds.
struct ImportToast: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if let message = model.importMessage {
            HStack(spacing: Space.md) {
                Text(message)
                if model.lastImportUndo != nil {
                    Button("Undo") { model.undoImport() }
                }
                Button { model.importMessage = nil } label: { Image(systemName: "xmark") }
                    .buttonStyle(.borderless)
                    .help(String(localized: "Close"))
                    .accessibilityLabel(Text("Close"))
            }
            .padding(.horizontal, Space.lg)
            .padding(.vertical, Space.sm)
            .background(.regularMaterial, in: Capsule())
            .padding(.top, Space.lg)
            .task(id: message) {
                try? await Task.sleep(for: .seconds(10))
                if model.importMessage == message { model.importMessage = nil }
            }
            .onAppear { AccessibilityNotification.Announcement(message).post() }
        }
    }
}
