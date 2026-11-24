import HangarKit
import SwiftUI

/// Health (S-042): what needs the person, grouped, each with its fix.
struct HealthPage: View {
    @Environment(AppModel.self) private var model
    @State private var fixing: String?

    var body: some View {
        Group {
            if model.healthIssues.isEmpty && !model.checkingHealth {
                ContentUnavailableView {
                    Label("Everything looks good", systemImage: "checkmark.seal")
                } description: {
                    Text("No moved files, unreadable bottles, signed-out Steam, or saves without a backup.")
                }
            } else {
                Form {
                    ForEach(HealthIssue.Kind.allCases, id: \.self) { kind in
                        let issues = model.healthIssues.filter { $0.kind == kind }
                        if !issues.isEmpty {
                            Section {
                                ForEach(issues) { row($0) }
                            } header: {
                                Label(kind.title, systemImage: kind.symbol)
                            }
                        }
                    }
                }
                .formStyle(.grouped)
            }
        }
        .navigationTitle("Health")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                if model.checkingHealth {
                    HStack(spacing: Space.sm) {
                        ProgressView().controlSize(.small)
                        Text("Checking…").foregroundStyle(.secondary)
                    }
                }
                Button { Task { await model.checkHealth(loadSaves: true) } } label: { Label("Check Again", systemImage: "arrow.clockwise") }
                    .help(String(localized: "Check the library again"))
                    .disabled(model.checkingHealth)
            }
        }
        .task { await model.checkHealth(loadSaves: true) }
    }

    private func row(_ issue: HealthIssue) -> some View {
        LabeledContent {
            Button(issue.kind.fix) {
                fixing = issue.id
                Task { await model.fixHealth(issue); fixing = nil }
            }
            .disabled(fixing == issue.id)
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(name(issue))
                Text(detail(issue)).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func name(_ issue: HealthIssue) -> String {
        switch issue {
        case let .filesMoved(id), let .neverBackedUp(id): model.game(id)?.title ?? id
        case let .bottleUnreadable(bottle), let .signedOut(bottle): String(localized: "Bottle \(bottle)")
        }
    }

    private func detail(_ issue: HealthIssue) -> String {
        switch issue {
        case let .filesMoved(id): model.game(id)?.path ?? ""
        case .bottleUnreadable: String(localized: "Open it once in CrossOver, then refresh.")
        case .signedOut: String(localized: "Its Steam games can't start until you sign in.")
        case .neverBackedUp: String(localized: "Its saves are on this Mac only.")
        }
    }
}
