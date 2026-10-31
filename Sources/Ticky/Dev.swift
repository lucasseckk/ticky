import SwiftUI
import AppKit

enum PanelSection: String, CaseIterable, Identifiable {
    case todos, dev
    var id: String { rawValue }
    var label: String {
        switch self {
        case .todos: return String(localized: "To-Dos")
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
    @State private var showRepoPicker = false
    @State private var newDevTodo = ""
    @State private var showAgentForm = false
    @State private var agentRepo = ""
    @State private var agentTitle = ""
    @State private var agentTask = ""
    @State private var agentCriteria = ""
    @State private var agentBusy = false
    @State private var urgentRepo: String?
    @State private var showIssuePicker = false
    @State private var issueQuery = ""
    @State private var agentDropTarget = false
    @State private var showDevArchive = false
    @State private var confirmClearDevArchive = false
    @AppStorage(DevStore.agentDoneHoursKey) private var agentDoneHours = DevStore.agentDoneHoursDefault
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
                ProgressView(String(localized: "Verbinde mit GitHub …")).frame(maxWidth: .infinity, maxHeight: .infinity)
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
                                if showDevArchive { devArchive } else {
                                urgentSection
                                agentSection
                                devTodos
                                section(.review, String(localized: "Review von mir angefordert"), "eyes")
                                section(.mine, String(localized: "Meine PRs"), "arrow.up.right")
                                section(.other, String(localized: "Sonstige"), "tray")
                                }
                                if !showDevArchive, PullRequest.Category.allCases.allSatisfy({ dev.pullRequests(in: $0).isEmpty }) {
                                    VStack(spacing: 10) {
                                        Image(systemName: "checkmark.seal").font(.system(size: 34))
                                        Text(dev.selectedRepos.isEmpty ? String(localized: "Wähle oben über „Repos“ Repositories aus.") : String(localized: "Keine offenen Pull Requests."))
                                    }
                                    .foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 40)
                                }
                            }
                            .padding(.horizontal, 4)
                            .padding(.vertical, 6)
                            .animation(.island, value: PullRequest.Category.allCases.flatMap { dev.pullRequests(in: $0) })
                            .animation(.island, value: store.todos.filter(\.isDev).map { [$0.id.uuidString, "\($0.done)"] })
                            .animation(.island, value: dev.visibleAgentIssues(hours: agentDoneHours))
                            .animation(.island, value: dev.urgentIssues)
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

    // MARK: Dringende Issues (#26): „[P1…“, Label `dringend`/`P1` oder mir zugewiesen

    @ViewBuilder private var urgentSection: some View {
        let all = dev.urgentIssues
        let repos = Array(Set(all.map(\.repo))).sorted()
        let shown = all.filter { urgentRepo == nil || $0.repo == urgentRepo }
        if !all.isEmpty {
            HStack(spacing: 6) {
                Label("Dringende Issues", systemImage: "flame").font(.headline)
                Text("\(shown.count)").font(.caption).foregroundStyle(.secondary)
                Spacer()
                if repos.count > 1 {
                    Menu(urgentRepo.map(repoName) ?? String(localized: "Alle Repos")) {
                        Button("Alle Repos") { withAnimation(.island) { urgentRepo = nil } }
                        Divider()
                        ForEach(repos, id: \.self) { repo in Button(repo) { withAnimation(.island) { urgentRepo = repo } } }
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                    .font(.caption.weight(.semibold))
                }
            }
            .padding(.horizontal, 4)
            byRepo("urgent", shown, repo: \.repo) { issue in urgentCard(issue) }
        }
    }

    private func repoName(_ repo: String) -> String { repo.split(separator: "/").last.map(String.init) ?? repo }

    /// With several repos selected, items are grouped under a small divider per repo (#88).
    /// `scope` keeps the group ids unique across sections; the lazy stack drops rows with duplicate ids.
    @ViewBuilder private func byRepo<Item: Identifiable, Card: View>(_ scope: String, _ items: [Item], repo: KeyPath<Item, String>, @ViewBuilder card: @escaping (Item) -> Card) -> some View {
        if dev.selectedRepos.count > 1 {
            ForEach(Array(Set(items.map { $0[keyPath: repo] })).sorted().map { "\(scope)|\($0)" }, id: \.self) { key in
                let name = String(key.dropFirst(scope.count + 1))
                HStack(spacing: 8) {
                    Text(repoName(name)).font(.caption2.weight(.semibold)).foregroundStyle(.secondary).fixedSize()
                    Rectangle().fill(Color.white.opacity(0.12)).frame(height: 1)
                }
                .padding(.horizontal, 6)
                .padding(.top, 2)
                ForEach(items.filter { $0[keyPath: repo] == name }) { card($0) }
            }
        } else {
            ForEach(items) { card($0) }
        }
    }

    /// Dropdown behind the „N Repos“ pill (#89); replaces the list that used to live in the settings.
    private var repoPicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Im Dev-Bereich anzeigen").font(.headline)
            if dev.availableRepos.isEmpty {
                Text("Keine Repositories gefunden.").font(.caption).foregroundStyle(.secondary)
            } else if dev.availableRepos.count > 10 {
                ScrollView { repoToggles }.frame(height: 260)
            } else {
                repoToggles
            }
        }
        .padding(16)
        .fixedSize()
    }

    /// The popover hugs this list, so it has no empty space next to or below it.
    private var repoToggles: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(dev.availableRepos, id: \.self) { repo in
                Toggle(repo, isOn: Binding(get: { dev.isSelected(repo) }, set: { selected in
                    dev.setSelected(repo, selected)
                    Task { await dev.refresh() }
                }))
                .toggleStyle(.checkbox)
            }
        }
    }

    private func urgentCard(_ issue: UrgentIssue) -> some View {
        let linked = store.todos.contains { $0.isDev && $0.link == issue.url }
        return HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 5) {
                Text(issue.title).font(.body.weight(.medium)).lineLimit(2)
                HStack(spacing: 5) {
                    InfoPill(text: "\(repoName(issue.repo)) #\(issue.number)", systemImage: "number")
                    ForEach(issue.labels.prefix(2), id: \.self) { InfoPill(text: $0, systemImage: "tag") }
                    if let assignee = issue.assignees.first { InfoPill(text: "@\(assignee)", systemImage: "person") }
                    InfoPill(text: issue.updated.formatted(.relative(presentation: .named)), systemImage: "clock")
                }
            }
            Spacer(minLength: 0)
            Menu {
                Button("Im Browser öffnen") { NSWorkspace.shared.open(issue.url) }
                Button(linked ? String(localized: "Bereits als Dev-To-do übernommen") : String(localized: "Als Dev-To-do übernehmen")) {
                    let priority: Priority = issue.rank.priority <= 1 ? .high : issue.rank.priority == 2 ? .normal : .low
                    withAnimation(.island) { store.save(Todo(title: "\(issue.title) (\(repoName(issue.repo)) #\(issue.number))", priority: priority, isDev: true, link: issue.url)) }
                    withAnimation(.island) { toast = (String(localized: "Als Dev-To-do gespeichert"), true) }
                }
                .disabled(linked)
                Button("An Agent übergeben (Label „agent“)") { handToAgent(issue) }
            } label: { Image(systemName: "ellipsis").font(.system(size: 12, weight: .bold)) }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
            .frame(width: 28, height: 28)
            .background(Color.white.opacity(0.12), in: Circle())
            .accessibilityLabel("Optionen für \(issue.title)")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .islandCard(stripe: issue.rank.priority <= 1 ? .red : .orange)
        .contentShape(RoundedRectangle(cornerRadius: 16))
        .draggable("issue:\(issue.id)")
        .onTapGesture { NSWorkspace.shared.open(issue.url) }
        .help("Issue im Browser öffnen")
    }

    // MARK: Agent-Aufgaben (#27): GitHub-Issues mit Label `agent`, lesbar für Coding-Agents

    /// Also a drop target: urgent issues dragged here become agent issues (#140).
    private var agentSection: some View {
        let issues = dev.visibleAgentIssues(hours: agentDoneHours)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Label("Agent-Aufgaben", systemImage: "cpu").font(.headline)
                Text("\(issues.filter { $0.status != .done }.count)").font(.caption).foregroundStyle(.secondary)
                Spacer()
                if !dev.offerableIssues.isEmpty {
                    Button { issueQuery = ""; showIssuePicker = true } label: {
                        Image(systemName: "tray.and.arrow.down")
                            .font(.caption.weight(.semibold))
                            .frame(width: 26, height: 26)
                            .islandCapsule()
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Issue hinzufügen")
                    .help("Vorhandenes offenes Issue als Agent-Aufgabe übernehmen")
                    .popover(isPresented: $showIssuePicker, arrowEdge: .bottom) { issuePicker }
                }
                Button { withAnimation(.island) { showAgentForm.toggle() } } label: {
                    Label(showAgentForm ? String(localized: "Schließen") : String(localized: "Neue Aufgabe"), systemImage: showAgentForm ? "xmark" : "plus")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .islandCapsule()
                }
                .buttonStyle(.plain)
                .disabled(dev.selectedRepos.isEmpty)
                .help("Legt ein GitHub-Issue mit Label „agent“ an, das Coding-Agents finden und abarbeiten können")
            }
            .padding(.horizontal, 4)
            if showAgentForm { agentForm }
            if issues.isEmpty && !showAgentForm {
                Text("Noch keine Issues mit Label „agent“. Agents finden sie mit `gh issue list --label agent`.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
            }
            byRepo("agent", issues, repo: \.repo) { issue in agentCard(issue) }
        }
        .padding(4)
        .background(RoundedRectangle(cornerRadius: 18).strokeBorder(Color.white.opacity(agentDropTarget ? 0.6 : 0), lineWidth: 1.5))
        .padding(-4)
        .dropDestination(for: String.self) { items, _ in handleAgentDrop(items) } isTargeted: { agentDropTarget = $0 }
    }

    /// Search over the loaded open issues that are not agent issues yet (#140).
    private var issuePicker: some View {
        let query = issueQuery.trimmingCharacters(in: .whitespaces)
        let issues = dev.offerableIssues.filter { query.isEmpty || $0.title.localizedCaseInsensitiveContains(query) || "#\($0.number)".contains(query) }
        return VStack(alignment: .leading, spacing: 10) {
            Text("Issue an Agent übergeben").font(.headline)
            TextField("Suchen", text: $issueQuery).textFieldStyle(.roundedBorder)
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(issues) { issue in
                        Button { showIssuePicker = false; handToAgent(issue) } label: {
                            HStack(spacing: 8) {
                                Text(issue.title).lineLimit(1)
                                Spacer(minLength: 8)
                                Text("\(repoName(issue.repo)) #\(issue.number)").font(.caption).foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 5)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    if issues.isEmpty { Text("Keine passenden Issues.").font(.caption).foregroundStyle(.secondary) }
                }
            }
            .frame(height: 240)
        }
        .padding(16)
        .frame(width: 360)
    }

    private func handToAgent(_ issue: UrgentIssue) {
        runAgentAction {
            try await dev.markAsAgent(issue)
            withAnimation(.island) { toast = (String(localized: "#\(issue.number) ist jetzt eine Agent-Aufgabe"), true) }
        }
    }

    private func handleAgentDrop(_ items: [String]) -> Bool {
        guard let issue = dev.openIssues.first(where: { items.contains("issue:\($0.id)") }), !issue.isAgent else { return false }
        handToAgent(issue)
        return true
    }

    private var agentForm: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("Repository", selection: $agentRepo) {
                ForEach(dev.selectedRepos, id: \.self) { Text($0).tag($0) }
            }
            TextField("Titel, z. B. „Suche um Tags erweitern“", text: $agentTitle)
                .textFieldStyle(.roundedBorder)
            TextField("Was soll der Agent tun? Kontext, betroffene Dateien …", text: $agentTask, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(3...6)
            TextField("Akzeptanzkriterien, eine pro Zeile", text: $agentCriteria, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(2...5)
            HStack {
                Text("Wird als Issue mit Label „agent“ angelegt.").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button(action: createAgentIssue) {
                    Group {
                        if agentBusy { ProgressView().controlSize(.small) } else { Text("Issue anlegen") }
                    }
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(Color.white, in: Capsule())
                }
                .buttonStyle(.plain)
                .disabled(agentBusy || agentTitle.trimmingCharacters(in: .whitespaces).isEmpty || agentTask.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(12)
        .islandSurface()
        .onAppear { if !dev.selectedRepos.contains(agentRepo) { agentRepo = dev.selectedRepos.first ?? "" } }
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    private func agentCard(_ issue: AgentIssue) -> some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 5) {
                Text(issue.title).font(.body.weight(.medium)).lineLimit(2).strikethrough(issue.status == .done)
                HStack(spacing: 5) {
                    agentStatusPill(issue)
                    InfoPill(text: "\(issue.repo.split(separator: "/").last.map(String.init) ?? issue.repo) #\(issue.number)", systemImage: "number")
                    if issue.author != dev.login { InfoPill(text: "@\(issue.author)", systemImage: "person", tint: .orange) }
                    InfoPill(text: issue.created.formatted(.relative(presentation: .named)), systemImage: "clock")
                }
            }
            Spacer(minLength: 0)
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(issue.prompt, forType: .string)
                withAnimation(.island) { toast = (String(localized: "Prompt für #\(issue.number) kopiert – in Claude Code oder Codex einfügen"), true) }
            } label: {
                Image(systemName: "doc.on.doc")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 28, height: 28)
                    .background(Color.white.opacity(0.12), in: Circle())
            }
            .accessibilityLabel("Prompt kopieren")
            .buttonStyle(.plain)
            .disabled(issue.status == .done)
            .help("Fertigen Prompt für einen Coding-Agent kopieren")
            Button { startClaude(issue) } label: {
                Image(systemName: "terminal")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 28, height: 28)
                    .background(Color.orange.opacity(0.28), in: Circle())
            }
            .accessibilityLabel("In Claude Code starten")
            .buttonStyle(.plain)
            .disabled(issue.status == .done)
            .help("Claude Code im Terminal mit diesem Prompt starten")
            Menu {
                Button("Issue im Browser öffnen") { NSWorkspace.shared.open(issue.url) }
                Button("Ordner für \(issue.repo) ändern …") { _ = ClaudeTerminal.chooseFolder(for: issue.repo) }
                if let pr = issue.pullRequest { Button("Pull Request öffnen") { NSWorkspace.shared.open(pr) } }
                if issue.status == .open { Button("Als „in Arbeit“ markieren") { runAgentAction { try await dev.setInProgress(issue, true) } } }
                if issue.status == .inProgress { Button("Zurück auf „offen“") { runAgentAction { try await dev.setInProgress(issue, false) } } }
                Divider()
                Button("Label „agent“ entfernen", role: .destructive) { runAgentAction { try await dev.removeAgentLabel(issue) } }
            } label: { Image(systemName: "ellipsis").font(.system(size: 12, weight: .bold)) }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
            .frame(width: 28, height: 28)
            .background(Color.white.opacity(0.12), in: Circle())
            .accessibilityLabel("Optionen für \(issue.title)")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .islandCard(stripe: Self.color(issue.status))
        .opacity(issue.status == .done ? 0.55 : 1)
        .contentShape(RoundedRectangle(cornerRadius: 16))
        .onTapGesture { NSWorkspace.shared.open(issue.url) }
        .help("Issue im Browser öffnen")
    }

    /// Copies the prompt as well, so it can be pasted again if the session is closed.
    private func startClaude(_ issue: AgentIssue) {
        guard let folder = ClaudeTerminal.folder(for: issue.repo) ?? ClaudeTerminal.chooseFolder(for: issue.repo) else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(issue.prompt, forType: .string)
        do {
            try ClaudeTerminal.start(prompt: issue.prompt, in: folder)
            withAnimation(.island) { toast = (String(localized: "Claude Code startet mit #\(issue.number) in \(folder.lastPathComponent)"), true) }
        } catch {
            withAnimation(.island) { toast = (String(localized: "Start fehlgeschlagen: \(error.localizedDescription)"), false) }
        }
    }

    @ViewBuilder private func agentStatusPill(_ issue: AgentIssue) -> some View {
        let tint = Self.color(issue.status)
        switch issue.status {
        case .open: InfoPill(text: String(localized: "Offen"), systemImage: "circle", tint: tint)
        case .inProgress: InfoPill(text: String(localized: "In Arbeit"), systemImage: "gearshape.2", tint: tint)
        case .prOpen:
            // CI of the linked pull request, taken from the already loaded pull requests.
            let ci = dev.pullRequests.first { $0.url == issue.pullRequest }?.ci
            Button { if let pr = issue.pullRequest { NSWorkspace.shared.open(pr) } } label: {
                HStack(spacing: 4) {
                    if let ci { CIDot(ci: ci).scaleEffect(0.7) }
                    InfoPill(text: "PR #\(issue.pullRequest?.lastPathComponent ?? "")", systemImage: "arrow.triangle.pull", tint: tint)
                }
            }
            .buttonStyle(.plain)
            .help("Verknüpften Pull Request öffnen")
        case .done: InfoPill(text: String(localized: "Erledigt"), systemImage: "checkmark", tint: tint)
        }
    }

    private static func color(_ status: AgentIssue.Status) -> Color {
        switch status {
        case .open: return .gray
        case .inProgress: return .yellow
        case .prOpen: return .blue
        case .done: return .green
        }
    }

    private func createAgentIssue() {
        let repo = agentRepo, title = agentTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let body = AgentIssue.body(task: agentTask, criteria: agentCriteria)
        agentBusy = true
        Task {
            do {
                try await dev.createAgentIssue(repo: repo, title: title, body: body)
                agentTitle = ""; agentTask = ""; agentCriteria = ""
                withAnimation(.island) { showAgentForm = false; toast = (String(localized: "Agent-Aufgabe angelegt"), true) }
            } catch {
                withAnimation(.island) { toast = (String(localized: "Anlegen fehlgeschlagen: \(error.localizedDescription)"), false) }
            }
            agentBusy = false
        }
    }

    private func runAgentAction(_ action: @escaping () async throws -> Void) {
        Task {
            do { try await action() } catch {
                withAnimation(.island) { toast = (String(localized: "Fehlgeschlagen: \(error.localizedDescription)"), false) }
            }
        }
    }

    /// Finished dev to-dos move to the Dev archive (#121).
    private var devItems: [Todo] {
        store.todos.filter { $0.isDev && !$0.done }.sorted { $0.priority.rawValue != $1.priority.rawValue ? $0.priority.rawValue > $1.priority.rawValue : $0.created < $1.created }
    }

    // MARK: Dev-Archiv (#121): erledigte Dev-To-dos und abgelaufene erledigte Agent-Aufgaben

    @ViewBuilder private var devArchive: some View {
        let todos = store.todos.filter { $0.isDev && $0.done }.sorted { $0.created > $1.created }
        let issues = dev.archivedAgentIssues(hours: agentDoneHours)
        HStack(spacing: 6) {
            Label("Dev-Archiv", systemImage: "archivebox").font(.headline)
            Spacer()
            if !todos.isEmpty {
                Button(confirmClearDevArchive ? String(localized: "Wirklich alle löschen?") : String(localized: "Dev-To-dos löschen")) {
                    if confirmClearDevArchive {
                        withAnimation(.island) { store.clearDevArchive() }
                        confirmClearDevArchive = false
                    } else {
                        confirmClearDevArchive = true
                    }
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(confirmClearDevArchive ? Color.red : Color.primary)
                .help("Löscht alle erledigten Dev-To-dos; Agent-Aufgaben bleiben auf GitHub")
            }
        }
        .padding(.horizontal, 4)
        if todos.isEmpty && issues.isEmpty {
            VStack(spacing: 10) {
                Image(systemName: "archivebox").font(.system(size: 34))
                Text("Das Dev-Archiv ist leer.")
            }
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 40)
        }
        if !todos.isEmpty {
            Text("Erledigte Dev-To-dos").font(.caption.weight(.semibold)).foregroundStyle(.secondary).padding(.horizontal, 4)
            ForEach(todos) { item in devRow(item) }
        }
        if !issues.isEmpty {
            Text("Erledigte Agent-Aufgaben").font(.caption.weight(.semibold)).foregroundStyle(.secondary).padding(.horizontal, 4)
            byRepo("archive", issues, repo: \.repo) { issue in agentCard(issue) }
        }
    }

    /// Dev to-dos (#49): collected from pull requests or added by hand, separate from the normal list.
    @ViewBuilder private var devTodos: some View {
        HStack(spacing: 6) {
            Label("Meine Dev-To-dos", systemImage: "checklist").font(.headline)
            Text("\(devItems.count)").font(.caption).foregroundStyle(.secondary)
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
            .accessibilityLabel(item.done ? String(localized: "Wieder öffnen: \(item.title)") : String(localized: "Erledigen: \(item.title)"))
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
        withAnimation(.island) { toast = (String(localized: "Als Dev-To-do gespeichert"), true) }
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
            Button { withAnimation(.island) { showDevArchive.toggle(); confirmClearDevArchive = false } } label: {
                Image(systemName: "archivebox")
                    .frame(width: 28, height: 28)
                    .foregroundStyle(showDevArchive ? Color.black : Color.white)
                    .background(showDevArchive ? Color.white : Color.white.opacity(0.1), in: Circle())
            }
            .buttonStyle(.plain)
            .help(showDevArchive ? String(localized: "Zurück zum Dev-Bereich") : String(localized: "Dev-Archiv: erledigte Dev-To-dos und Agent-Aufgaben"))
            .accessibilityLabel("Dev-Archiv")
            if let updated = dev.lastUpdated {
                Text(updated.formatted(date: .omitted, time: .shortened))
                    .foregroundStyle(.secondary)
                    .help("Zuletzt aktualisiert")
            }
            Button { showRepoPicker.toggle() } label: {
                Text("\(dev.selectedRepos.count) Repos ▾")
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .islandCapsule()
            }
            .buttonStyle(.plain)
            .help("Repositories für den Dev-Bereich auswählen")
            .popover(isPresented: $showRepoPicker, arrowEdge: .bottom) { repoPicker }
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
            counter("xmark.circle", String(localized: "CI rot"), failingCount, .red) {
                let target = PullRequest.Category.allCases.first { dev.pullRequests(in: $0).contains { $0.ci == .failure } } ?? .review
                withAnimation(.island) { proxy.scrollTo(target, anchor: .top) }
            }
            counter("arrow.up.right", String(localized: "Meine PRs"), dev.pullRequests(in: .mine).count, .blue) { withAnimation(.island) { proxy.scrollTo(PullRequest.Category.mine, anchor: .top) } }
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
            .background(count > 0 ? tint.opacity(0.12) : .clear, in: Capsule())
            .overlay(Capsule().strokeBorder(count > 0 ? tint.opacity(0.6) : Color.white.opacity(0.1)))
            .shadow(color: count > 0 ? tint.opacity(0.3) : .clear, radius: 5)
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
            byRepo("\(category)", items, repo: \.repo) { pr in card(pr) }
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
            VStack(alignment: .trailing, spacing: 5) {
            Button {
                if confirming { merge(pr) } else { withAnimation(.island) { confirmMergeID = pr.id } }
            } label: {
                Group {
                    if mergingID == pr.id { ProgressView().controlSize(.small) } else { Text(confirming ? String(localized: "Wirklich mergen?") : String(localized: "Mergen")) }
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
            .help(pr.canMerge ? String(localized: "Prüft die CI erneut und mergt mit der Strategie des Repos") : pr.isDraft ? String(localized: "Draft-PRs können nicht gemergt werden") : String(localized: "Erst wenn die CI grün ist"))
            Button { addTodo(for: pr) } label: {
                Label(hasTodo(for: pr) ? String(localized: "Als To-do ✓") : String(localized: "Als To-do"), systemImage: "plus")
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
                withAnimation(.island) { toast = (String(localized: "PR #\(pr.number) gemergt"), true) }
            } catch {
                withAnimation(.island) { toast = (String(localized: "Merge fehlgeschlagen: \(error.localizedDescription)"), false) }
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
                 ? String(localized: "Der Dev-Bereich nutzt die GitHub CLI, damit die App selbst keine Zugangsdaten speichert. Im Terminal:")
                 : error == .notLoggedIn ? String(localized: "Melde die GitHub CLI einmalig an. Im Terminal:") : String(localized: "Prüfe deine Verbindung und versuche es erneut."))
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
        case .success: return String(localized: "CI grün")
        case .failure: return String(localized: "CI rot")
        case .pending: return String(localized: "CI läuft")
        case .none: return String(localized: "Keine CI")
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

/// Opens Claude Code in Terminal for an agent issue (#79), in the repo's local folder chosen once per repo.
@MainActor enum ClaudeTerminal {
    private static let foldersKey = "repoFolders"

    static func folder(for repo: String) -> URL? {
        guard let path = (UserDefaults.standard.dictionary(forKey: foldersKey) as? [String: String])?[repo],
              FileManager.default.fileExists(atPath: path) else { return nil }
        return URL(fileURLWithPath: path)
    }

    static func chooseFolder(for repo: String) -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.message = String(localized: "Lokalen Ordner von \(repo) wählen – dort startet Claude Code.")
        panel.prompt = String(localized: "Ordner wählen")
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        var folders = UserDefaults.standard.dictionary(forKey: foldersKey) as? [String: String] ?? [:]
        folders[repo] = url.path
        UserDefaults.standard.set(folders, forKey: foldersKey)
        return url
    }

    static func start(prompt: String, in folder: URL) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("todo-list-claude", isDirectory: true)
        let id = UUID().uuidString
        let promptFile = directory.appendingPathComponent("\(id).txt")
        let script = directory.appendingPathComponent("\(id).command")
        try writePrivately(Data(prompt.utf8), to: promptFile)
        try writePrivately(Data(ClaudeScript.make(folder: folder.path, promptFile: promptFile.path).utf8), to: script)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: script.path)
        guard let terminal = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Terminal") else { return }
        NSWorkspace.shared.open([script], withApplicationAt: terminal, configuration: NSWorkspace.OpenConfiguration())
    }
}
