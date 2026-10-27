import SwiftUI
import AppKit

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
    let openSettings: () -> Void
    @State private var confirmMergeID: String?
    @State private var mergingID: String?
    @State private var toast: (text: String, success: Bool)?

    var body: some View {
        Group {
            if case .failed(let error) = dev.connection, dev.login == nil, dev.availableRepos.isEmpty {
                setupHint(error)
            } else if dev.connection == .unknown {
                ProgressView("Verbinde mit GitHub …").frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    VStack(alignment: .leading, spacing: 10) {
                        statusRow
                        counterRow(proxy)
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 8) {
                                if !dev.failedRepos.isEmpty {
                                    Label("Nicht geladen: \(dev.failedRepos.joined(separator: ", "))", systemImage: "exclamationmark.triangle.fill")
                                        .font(.caption)
                                        .foregroundStyle(.orange)
                                }
                                section(.review, "Review von mir angefordert", "eyes")
                                section(.mine, "Meine PRs", "arrow.up.right")
                                section(.other, "Sonstige", "tray")
                                if PullRequest.Category.allCases.allSatisfy({ dev.pullRequests(in: $0).isEmpty }) {
                                    VStack(spacing: 10) {
                                        Image(systemName: "checkmark.seal").font(.system(size: 34))
                                        Text(dev.selectedRepos.isEmpty ? "Wähle in den Einstellungen Repositories aus." : "Keine offenen Pull Requests.")
                                    }
                                    .foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 40)
                                }
                            }
                            .padding(.horizontal, 4)
                            .padding(.vertical, 6)
                            .animation(.island, value: dev.pullRequests)
                        }
                    }
                }
            }
        }
        .overlay(alignment: .bottom) {
            if let toast {
                Label(toast.text, systemImage: toast.success ? "checkmark.circle.fill" : "xmark.octagon.fill")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(toast.success ? Color.green : Color.red)
                    .lineLimit(2)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Color.black, in: Capsule())
                    .overlay(Capsule().strokeBorder((toast.success ? Color.green : Color.red).opacity(0.5)))
                    .shadow(color: (toast.success ? Color.green : Color.red).opacity(0.4), radius: 10)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .task(id: toast.text) {
                        try? await Task.sleep(for: .seconds(3))
                        withAnimation(.island) { self.toast = nil }
                    }
            }
        }
        // On open and every 2 minutes while the panel is visible; cancelled when it closes.
        .task {
            while !Task.isCancelled {
                await dev.refresh()
                try? await Task.sleep(for: .seconds(120))
            }
        }
    }

    private var reviewCount: Int { dev.pullRequests(in: .review).count }
    private var failingCount: Int { PullRequest.Category.allCases.flatMap { dev.pullRequests(in: $0) }.filter { $0.ci == .failure }.count }

    private var statusRow: some View {
        HStack(spacing: 6) {
            if case .failed(let error) = dev.connection {
                Label(error.localizedDescription, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .lineLimit(1)
            } else if let login = dev.login {
                Label("@\(login)", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }
            Spacer()
            if let updated = dev.lastUpdated {
                Text(updated.formatted(date: .omitted, time: .shortened))
                    .foregroundStyle(.secondary)
                    .help("Zuletzt aktualisiert")
            }
            Button(action: openSettings) {
                Text("\(dev.selectedRepos.count) Repos ▸")
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .islandCapsule()
            }
            .buttonStyle(.plain)
            .help("Repositories in den Einstellungen auswählen")
            Button { Task { await dev.refresh() } } label: {
                Group {
                    if dev.isRefreshing { ProgressView().controlSize(.small) } else { Image(systemName: "arrow.clockwise") }
                }
                .frame(width: 28, height: 28)
                .background(Color.white.opacity(0.1), in: Circle())
            }
            .buttonStyle(.plain)
            .disabled(dev.isRefreshing)
            .help("Von GitHub aktualisieren")
            .accessibilityLabel("Aktualisieren")
        }
        .font(.caption.weight(.semibold))
    }

    private func counterRow(_ proxy: ScrollViewProxy) -> some View {
        HStack(spacing: 6) {
            counter("eyes", "Review", reviewCount, .orange) { withAnimation(.island) { proxy.scrollTo(PullRequest.Category.review, anchor: .top) } }
            counter("xmark.circle", "CI rot", failingCount, .red) {
                let target = PullRequest.Category.allCases.first { dev.pullRequests(in: $0).contains { $0.ci == .failure } } ?? .review
                withAnimation(.island) { proxy.scrollTo(target, anchor: .top) }
            }
            counter("arrow.up.right", "Meine PRs", dev.pullRequests(in: .mine).count, .blue) { withAnimation(.island) { proxy.scrollTo(PullRequest.Category.mine, anchor: .top) } }
        }
    }

    private func counter(_ systemImage: String, _ label: String, _ count: Int, _ tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: systemImage)
                Text("\(count)").monospacedDigit().contentTransition(.numericText())
                Text(label).foregroundStyle(.secondary)
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(count > 0 ? tint : Color.secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 7)
            .background(Color.black, in: Capsule())
            .overlay(Capsule().strokeBorder(count > 0 ? tint.opacity(0.6) : Color.white.opacity(0.1)))
            .shadow(color: count > 0 ? tint.opacity(0.35) : .clear, radius: 6)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(label): \(count)")
    }

    @ViewBuilder private func section(_ category: PullRequest.Category, _ title: String, _ systemImage: String) -> some View {
        let items = dev.pullRequests(in: category)
        if !items.isEmpty {
            HStack(spacing: 6) {
                Label(title, systemImage: systemImage).font(.headline)
                Text("\(items.count)").font(.caption).foregroundStyle(.secondary)
            }
            .padding(.top, 6)
            .padding(.horizontal, 4)
            .id(category)
            ForEach(items) { pr in card(pr) }
        }
    }

    private func card(_ pr: PullRequest) -> some View {
        let confirming = confirmMergeID == pr.id
        return HStack(alignment: .center, spacing: 10) {
            CIDot(ci: pr.ci)
            VStack(alignment: .leading, spacing: 5) {
                Text(pr.title).font(.body.weight(.medium)).lineLimit(2)
                HStack(spacing: 5) {
                    InfoPill(text: "\(pr.repo.split(separator: "/").last.map(String.init) ?? pr.repo) #\(pr.number)", systemImage: "arrow.triangle.pull")
                    if pr.author != dev.login { InfoPill(text: "@\(pr.author)", systemImage: "person") }
                    InfoPill(text: pr.created.formatted(.relative(presentation: .named)), systemImage: "clock")
                    if pr.isDraft { InfoPill(text: "Draft", systemImage: "pencil", tint: .gray) }
                }
            }
            Spacer(minLength: 0)
            Button {
                if confirming { merge(pr) } else { withAnimation(.island) { confirmMergeID = pr.id } }
            } label: {
                Group {
                    if mergingID == pr.id { ProgressView().controlSize(.small) } else { Text(confirming ? "Wirklich mergen?" : "Mergen") }
                }
                .font(.caption.weight(.bold))
                .foregroundStyle(confirming ? Color.white : Color.black)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(confirming ? Color.red : Color.white, in: Capsule())
                .shadow(color: confirming ? .red.opacity(0.7) : .clear, radius: 8)
            }
            .buttonStyle(.plain)
            .disabled(!pr.canMerge || mergingID != nil)
            .opacity(pr.canMerge ? 1 : 0.35)
            .help(pr.canMerge ? "Mit Merge-Commit zusammenführen" : pr.isDraft ? "Draft-PRs können nicht gemergt werden" : "Erst wenn die CI grün ist")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .islandCard(tint: CIDot.color(pr.ci), shimmer: false)
        .contentShape(RoundedRectangle(cornerRadius: 18))
        .onTapGesture { NSWorkspace.shared.open(pr.url) }
        .help("Im Browser öffnen")
        .onHover { inside in if !inside && confirming { withAnimation(.island) { confirmMergeID = nil } } }
        .transition(.asymmetric(insertion: .opacity, removal: .scale(scale: 0.6).combined(with: .opacity)))
    }

    private func merge(_ pr: PullRequest) {
        mergingID = pr.id
        Task {
            do {
                try await dev.merge(pr)
                withAnimation(.island) { toast = ("PR #\(pr.number) gemergt", true) }
            } catch {
                withAnimation(.island) { toast = ("Merge fehlgeschlagen: \(error.localizedDescription)", false) }
            }
            mergingID = nil
            confirmMergeID = nil
        }
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
                    .islandSurface(cornerRadius: 10)
            }
            Button("Erneut prüfen") { Task { await dev.refresh() } }
                .disabled(dev.isRefreshing)
        }
        .foregroundStyle(.secondary)
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Glowing CI status dot; pulses while checks are still running.
struct CIDot: View {
    let ci: PullRequest.CI
    @State private var pulse = false

    static func color(_ ci: PullRequest.CI) -> Color {
        switch ci {
        case .success: return .green
        case .failure: return .red
        case .pending: return .yellow
        case .none: return .gray
        }
    }

    var body: some View {
        Circle()
            .fill(Self.color(ci))
            .frame(width: 10, height: 10)
            .shadow(color: Self.color(ci), radius: pulse ? 7 : 3)
            .opacity(ci == .pending && pulse ? 0.45 : 1)
            .onAppear {
                guard ci == .pending else { return }
                withAnimation(.easeInOut(duration: 0.9).repeatForever()) { pulse = true }
            }
            .accessibilityLabel(label)
    }

    private var label: String {
        switch ci {
        case .success: return "CI grün"
        case .failure: return "CI rot"
        case .pending: return "CI läuft"
        case .none: return "Keine CI"
        }
    }
}
