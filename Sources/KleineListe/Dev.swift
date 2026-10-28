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
    @ObservedObject var store: Store
    let openSettings: () -> Void
    @State private var newDevTodo = ""
    @AppStorage("highPriorityColor") private var highPriorityColorHex = "#C24033"
    @AppStorage("mediumPriorityColor") private var mediumPriorityColorHex = "#E0A63D"
    @AppStorage("lowPriorityColor") private var lowPriorityColorHex = "#94BD80"
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
                                devTodos
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
                            .animation(.island, value: PullRequest.Category.allCases.flatMap { dev.pullRequests(in: $0) })
                            .animation(.island, value: store.todos.filter(\.isDev).map(\.id))
                        }
                    }
                }
            }
        }
        .overlay(alignment: .bottom) {
            if let toast {
                Label(toast.text, systemImage: toast.success ? "checkmark.circle.fill" : "xmark.octagon.fill")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Color.black, in: Capsule())
                    .overlay(Capsule().strokeBorder(Color.white.opacity(0.15)))
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

    private var devItems: [Todo] {
        store.todos.filter(\.isDev).sorted { $0.done != $1.done ? !$0.done : $0.priority.rawValue != $1.priority.rawValue ? $0.priority.rawValue > $1.priority.rawValue : $0.created < $1.created }
    }

    /// Dev to-dos (#49): collected from pull requests or added by hand, separate from the normal list.
    @ViewBuilder private var devTodos: some View {
        HStack(spacing: 6) {
            Label("Dev-To-dos", systemImage: "checklist").font(.headline)
            Text("\(devItems.filter { !$0.done }.count)").font(.caption).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 4)
        HStack(spacing: 6) {
            TextField("Dev-To-do hinzufügen", text: $newDevTodo)
                .textFieldStyle(.plain)
                .onSubmit(addDevTodo)
            Button(action: addDevTodo) {
                Image(systemName: "plus").font(.system(size: 12, weight: .bold)).foregroundStyle(.black)
                    .frame(width: 24, height: 24).background(Color.white, in: Circle())
            }
            .buttonStyle(.plain)
            .disabled(newDevTodo.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .accessibilityLabel("Dev-To-do hinzufügen")
        }
        .padding(.leading, 14)
        .padding(.trailing, 5)
        .padding(.vertical, 5)
        .islandCapsule()
        ForEach(devItems) { item in devRow(item) }
    }

    private func devRow(_ item: Todo) -> some View {
        HStack(spacing: 10) {
            Button { withAnimation(.island) { store.toggle(item) } } label: {
                Image(systemName: item.done ? "checkmark.circle.fill" : "circle").font(.title3)
                    .foregroundStyle(Color.white.opacity(item.done ? 0.5 : 0.85))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(item.done ? "Wieder öffnen: \(item.title)" : "Erledigen: \(item.title)")
            VStack(alignment: .leading, spacing: 5) {
                DevTitleField(title: item.title, done: item.done) { title in
                    guard var todo = store.todos.first(where: { $0.id == item.id }), todo.title != title else { return }
                    todo.title = title
                    store.save(todo)
                }
                if let link = item.link {
                    Button { NSWorkspace.shared.open(link) } label: {
                        InfoPill(text: link.pathComponents.suffix(3).joined(separator: "/"), systemImage: "link")
                    }
                    .buttonStyle(.plain)
                    .help(link.absoluteString)
                }
            }
            Spacer(minLength: 0)
            Menu {
                Picker("Priorität", selection: Binding(get: { item.priority }, set: { priority in
                    guard var todo = store.todos.first(where: { $0.id == item.id }) else { return }
                    todo.priority = priority
                    withAnimation(.island) { store.save(todo) }
                })) {
                    ForEach(Priority.allCases.reversed()) { Text($0.label).tag($0) }
                }
                Divider()
                Button("Löschen", role: .destructive) { withAnimation(.island) { store.delete(item) } }
            } label: { Image(systemName: "ellipsis").font(.system(size: 12, weight: .bold)) }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
            .frame(width: 28, height: 28)
            .background(Color.white.opacity(0.12), in: Circle())
            .accessibilityLabel("Optionen für \(item.title)")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .islandCard(stripe: color(for: item.priority))
        .opacity(item.done ? 0.55 : 1)
        .transition(.asymmetric(insertion: .scale(scale: 0.6, anchor: .top).combined(with: .opacity), removal: .opacity))
    }

    private func color(for priority: Priority) -> Color {
        switch priority {
        case .high: return Color(hex: highPriorityColorHex)
        case .normal: return Color(hex: mediumPriorityColorHex)
        case .low: return Color(hex: lowPriorityColorHex)
        }
    }

    private func addDevTodo() {
        guard !newDevTodo.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        withAnimation(.island) { store.save(Todo(title: newDevTodo, isDev: true)) }
        newDevTodo = ""
    }

    private func hasTodo(for pr: PullRequest) -> Bool { store.todos.contains { $0.isDev && $0.link == pr.url } }

    private func addTodo(for pr: PullRequest) {
        let repoName = pr.repo.split(separator: "/").last.map(String.init) ?? pr.repo
        let priority: Priority = pr.category(for: dev.login) == .review ? .high : .normal
        withAnimation(.island) { store.save(Todo(title: "Review: \(pr.title) (\(repoName) #\(pr.number))", priority: priority, isDev: true, link: pr.url)) }
        withAnimation(.island) { toast = ("Als Dev-To-do gespeichert", true) }
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
                    .shadow(color: .green.opacity(0.8), radius: 5)
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
            counter("eyes", "Review", reviewCount) { withAnimation(.island) { proxy.scrollTo(PullRequest.Category.review, anchor: .top) } }
            counter("xmark.circle", "CI rot", failingCount) {
                let target = PullRequest.Category.allCases.first { dev.pullRequests(in: $0).contains { $0.ci == .failure } } ?? .review
                withAnimation(.island) { proxy.scrollTo(target, anchor: .top) }
            }
            counter("arrow.up.right", "Meine PRs", dev.pullRequests(in: .mine).count) { withAnimation(.island) { proxy.scrollTo(PullRequest.Category.mine, anchor: .top) } }
        }
    }

    private func counter(_ systemImage: String, _ label: String, _ count: Int, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: systemImage)
                Text("\(count)").monospacedDigit().contentTransition(.numericText())
                Text(label).foregroundStyle(.secondary)
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(count > 0 ? Color.primary : Color.secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 7)
            .background(Color.black, in: Capsule())
            .overlay(Capsule().strokeBorder(Color.white.opacity(count > 0 ? 0.25 : 0.1)))
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
                HStack(spacing: 6) {
                    Text(pr.title).font(.body.weight(.medium)).lineLimit(2)
                    if pr.isExample {
                        Text("Beispiel").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                            .padding(.horizontal, 6).padding(.vertical, 1)
                            .overlay(Capsule().strokeBorder(Color.white.opacity(0.25)))
                    }
                }
                HStack(spacing: 5) {
                    InfoPill(text: "\(pr.repo.split(separator: "/").last.map(String.init) ?? pr.repo) #\(pr.number)", systemImage: "arrow.triangle.pull")
                    if pr.author != dev.login { InfoPill(text: "@\(pr.author)", systemImage: "person") }
                    InfoPill(text: pr.created.formatted(.relative(presentation: .named)), systemImage: "clock")
                    if pr.isDraft { InfoPill(text: "Draft", systemImage: "pencil", tint: .gray) }
                }
            }
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 5) {
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
            }
            .buttonStyle(.plain)
            .disabled(!pr.canMerge || mergingID != nil)
            .opacity(pr.canMerge ? 1 : 0.35)
            .help(pr.canMerge ? "Mit Merge-Commit zusammenführen" : pr.isDraft ? "Draft-PRs können nicht gemergt werden" : "Erst wenn die CI grün ist")
            Button { addTodo(for: pr) } label: {
                Label(hasTodo(for: pr) ? "Als To-do ✓" : "Als To-do", systemImage: "plus")
                    .labelStyle(.titleOnly)
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .islandCapsule()
            }
            .buttonStyle(.plain)
            .disabled(hasTodo(for: pr))
            .help("In die Dev-To-dos übernehmen")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .islandCard()
        .contentShape(RoundedRectangle(cornerRadius: 16))
        .onTapGesture { if !pr.isExample { NSWorkspace.shared.open(pr.url) } }
        .help("Im Browser öffnen")
        .onHover { inside in if !inside && confirming { withAnimation(.island) { confirmMergeID = nil } } }
        .transition(.asymmetric(insertion: .opacity, removal: .scale(scale: 0.6).combined(with: .opacity)))
    }

    private func merge(_ pr: PullRequest) {
        mergingID = pr.id
        Task {
            do {
                try await dev.merge(pr)
                withAnimation(.island) { toast = (pr.isExample ? "Beispiel-PR #\(pr.number) gemergt (nur zur Ansicht)" : "PR #\(pr.number) gemergt", true) }
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

/// Editable title that saves on Return or when focus leaves, so trimming never fights the typing.
private struct DevTitleField: View {
    let title: String
    let done: Bool
    let onCommit: (String) -> Void
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        TextField("Titel", text: $text, axis: .vertical)
            .textFieldStyle(.plain)
            .font(.body.weight(.medium))
            .strikethrough(done)
            .focused($focused)
            .onSubmit { onCommit(text) }
            .onChange(of: focused) { _, isFocused in if !isFocused { onCommit(text) } }
            .onAppear { text = title }
            .onChange(of: title) { _, newTitle in if !focused { text = newTitle } }
    }
}
