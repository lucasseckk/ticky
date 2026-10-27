import SwiftUI

enum PanelSection: String, CaseIterable, Identifiable {
    case todos, dev
    var id: String { rawValue }
    var label: String {
        switch self {
        case .todos: return "To-Dos"
        case .dev: return "Dev"
        }
    }
    var systemImage: String {
        switch self {
        case .todos: return "checklist"
        case .dev: return "chevron.left.forwardslash.chevron.right"
        }
    }
}

/// Dev section: pull requests, urgent issues and agent issues from GitHub (see #22).
struct DevView: View {
    @ObservedObject var dev: DevStore

    var body: some View {
        Group {
            if case .failed(let error) = dev.connection, dev.login == nil, dev.availableRepos.isEmpty {
                setupHint(error)
            } else if dev.connection == .unknown {
                ProgressView("Verbinde mit GitHub …").frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        statusRow
                        SettingsCard(title: "Repositories", systemImage: "folder", subtitle: "\(dev.selectedRepos.count) von \(dev.availableRepos.count) ausgewählt – nur diese erscheinen im Dev-Bereich.") {
                            ForEach(dev.availableRepos, id: \.self) { repo in
                                Toggle(repo, isOn: Binding(get: { dev.isSelected(repo) }, set: { dev.setSelected(repo, $0) }))
                                    .toggleStyle(.checkbox)
                            }
                        }
                        SettingsCard(title: "Pull Requests und Issues", systemImage: "arrow.triangle.pull", subtitle: "Folgt mit #25 (Pull Requests), #26 (dringende Issues) und #27 (Agent-Issues).") {
                            EmptyView()
                        }
                    }
                }
            }
        }
        .task { await dev.refreshIfStale() }
    }

    private var statusRow: some View {
        HStack(spacing: 8) {
            if case .failed(let error) = dev.connection {
                Label(error.localizedDescription, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .lineLimit(2)
            } else if let login = dev.login {
                Label("Verbunden als @\(login)", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }
            Spacer()
            if let updated = dev.lastUpdated {
                Text("Stand \(updated.formatted(date: .omitted, time: .shortened))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Button { Task { await dev.refresh() } } label: {
                if dev.isRefreshing { ProgressView().controlSize(.small) } else { Image(systemName: "arrow.clockwise") }
            }
            .buttonStyle(.plain)
            .disabled(dev.isRefreshing)
            .help("Von GitHub aktualisieren")
            .accessibilityLabel("Aktualisieren")
        }
        .font(.callout)
    }

    private func setupHint(_ error: GitHubError) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "chevron.left.forwardslash.chevron.right").font(.system(size: 34))
            Text(error.localizedDescription).font(.headline)
            Text(error == .missingCLI
                 ? "Der Dev-Bereich nutzt die GitHub CLI, damit die App selbst keine Zugangsdaten speichert. Im Terminal:"
                 : error == .notLoggedIn ? "Melde die GitHub CLI einmalig an. Im Terminal:" : "Prüfe deine Verbindung und versuche es erneut.")
                .font(.callout)
                .multilineTextAlignment(.center)
            if error == .missingCLI || error == .notLoggedIn {
                Text(error == .missingCLI ? "brew install gh\ngh auth login" : "gh auth login")
                    .font(.system(.callout, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(10)
                    .background(.background.opacity(0.6), in: RoundedRectangle(cornerRadius: 8))
            }
            Button("Erneut prüfen") { Task { await dev.refresh() } }
                .disabled(dev.isRefreshing)
        }
        .foregroundStyle(.secondary)
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
