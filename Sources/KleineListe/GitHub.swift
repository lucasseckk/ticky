import Foundation

enum GitHubError: LocalizedError, Equatable {
    case missingCLI, notLoggedIn, timedOut, failed(String)

    var errorDescription: String? {
        switch self {
        case .missingCLI: return "Die GitHub CLI (gh) ist nicht installiert."
        case .notLoggedIn: return "Die GitHub CLI ist nicht angemeldet."
        case .timedOut: return "GitHub hat nicht rechtzeitig geantwortet."
        case .failed(let message): return message
        }
    }

    /// Exit code 4 is gh's "authentication required"; its message also names `gh auth login`.
    static func classify(exitCode: Int32, stderr: String) -> GitHubError {
        if exitCode == 4 || stderr.contains("gh auth login") { return .notLoggedIn }
        let message = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        return .failed(message.isEmpty ? "gh wurde mit Code \(exitCode) beendet." : message)
    }
}

/// Runs the user's already authenticated GitHub CLI, so the app never stores a token itself.
struct GitHubCLI: Sendable {
    let executable: URL

    /// GUI apps don't inherit the shell PATH, so look in the usual install locations.
    static let candidates = ["/opt/homebrew/bin/gh", "/usr/local/bin/gh", "/usr/bin/gh"]

    static func locate(in paths: [String] = candidates) -> GitHubCLI? {
        paths.first { FileManager.default.isExecutableFile(atPath: $0) }.map { GitHubCLI(executable: URL(fileURLWithPath: $0)) }
    }

    func run(_ arguments: [String], timeout: TimeInterval = 20) async throws -> Data {
        try await Task.detached { try runSync(arguments, timeout: timeout) }.value
    }

    func runSync(_ arguments: [String], timeout: TimeInterval = 20) throws -> Data {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        var environment = ProcessInfo.processInfo.environment
        environment["GH_PROMPT_DISABLED"] = "1"
        environment["NO_COLOR"] = "1"
        process.environment = environment
        let output = Pipe(), errors = Pipe()
        process.standardOutput = output
        process.standardError = errors
        try process.run()
        let timer = DispatchWorkItem { if process.isRunning { process.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: timer)
        // Read stderr concurrently so a full pipe can never block the process.
        var errorData = Data()
        let errorReader = DispatchWorkItem { errorData = errors.fileHandleForReading.readDataToEndOfFile() }
        DispatchQueue.global().async(execute: errorReader)
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        errorReader.wait()
        timer.cancel()
        if process.terminationReason == .uncaughtSignal { throw GitHubError.timedOut }
        guard process.terminationStatus == 0 else {
            throw GitHubError.classify(exitCode: process.terminationStatus, stderr: String(decoding: errorData, as: UTF8.self))
        }
        return data
    }
}

func nonEmptyLines(_ data: Data) -> [String] {
    String(decoding: data, as: UTF8.self).split(whereSeparator: \.isNewline).map(String.init).filter { !$0.isEmpty }
}

struct PullRequest: Identifiable, Equatable, Sendable {
    enum CI: Sendable { case none, pending, success, failure }
    enum Category: CaseIterable, Sendable { case review, mine, other }

    let repo: String
    let number: Int
    let title: String
    let author: String
    let created: Date
    let isDraft: Bool
    let url: URL
    let reviewRequests: [String]
    let ci: CI
    var id: String { "\(repo)#\(number)" }

    /// Merging is only offered when nothing is failing or still running.
    var canMerge: Bool { !isDraft && (ci == .success || ci == .none) }

    func category(for login: String?) -> Category {
        guard let login else { return .other }
        if reviewRequests.contains(login) { return .review }
        return author == login ? .mine : .other
    }

    static let jsonFields = "number,title,author,createdAt,isDraft,url,reviewRequests,statusCheckRollup"

    /// Parses `gh pr list --json` output.
    static func parse(_ data: Data, repo: String) throws -> [PullRequest] {
        struct Raw: Decodable {
            struct Login: Decodable { let login: String? }
            struct Request: Decodable { let login: String?; let slug: String?; let name: String? }
            struct Check: Decodable { let status: String?; let conclusion: String?; let state: String? }
            let number: Int, title: String, author: Login?, createdAt: Date, isDraft: Bool, url: URL
            let reviewRequests: [Request]?, statusCheckRollup: [Check]?
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode([Raw].self, from: data).map { raw in
            PullRequest(repo: repo, number: raw.number, title: raw.title, author: raw.author?.login ?? "",
                        created: raw.createdAt, isDraft: raw.isDraft, url: raw.url,
                        reviewRequests: (raw.reviewRequests ?? []).compactMap { $0.login ?? $0.slug ?? $0.name },
                        ci: ci(of: (raw.statusCheckRollup ?? []).map { ($0.status, $0.conclusion, $0.state) }))
        }
    }

    /// Check runs report status/conclusion, legacy commit statuses report state.
    static func ci(of checks: [(status: String?, conclusion: String?, state: String?)]) -> CI {
        guard !checks.isEmpty else { return .none }
        let failed: Set = ["FAILURE", "ERROR", "CANCELLED", "TIMED_OUT", "ACTION_REQUIRED", "STARTUP_FAILURE"]
        if checks.contains(where: { failed.contains($0.conclusion ?? "") || failed.contains($0.state ?? "") }) { return .failure }
        if checks.contains(where: { ($0.status.map { $0 != "COMPLETED" } ?? false) || ["PENDING", "EXPECTED"].contains($0.state ?? "") }) { return .pending }
        return .success
    }
}

/// A GitHub issue labelled `agent`: work a coding agent can pick up on its own (#27).
struct AgentIssue: Identifiable, Equatable, Sendable {
    enum Status: Int, Sendable { case open, inProgress, prOpen, done }

    static let label = "agent"
    static let inProgressLabel = "agent:in-arbeit"
    static let jsonFields = "number,title,body,url,createdAt,closedAt,state,labels,closedByPullRequestsReferences"

    let repo: String
    let number: Int
    let title: String
    let body: String
    let url: URL
    let created: Date
    let closed: Date?
    let status: Status
    let pullRequest: URL?

    var id: String { "\(repo)#\(number)" }

    /// Ready-to-paste instruction for Claude Code, Codex or another agent.
    var prompt: String {
        """
        Bearbeite das GitHub-Issue #\(number) im Repository \(repo): „\(title)“.

        \(body.trimmingCharacters(in: .whitespacesAndNewlines))

        Vorgehen:
        - Lies zuerst AGENTS.md und hole alle Details mit `gh issue view \(number) -R \(repo) --comments`.
        - Setze das Label `\(Self.inProgressLabel)`, solange du daran arbeitest: `gh issue edit \(number) -R \(repo) --add-label \(Self.inProgressLabel)`.
        - Arbeite auf einem neuen Branch, prüfe dein Ergebnis und öffne einen Pull Request mit „Closes #\(number)“ in der Beschreibung.
        """
    }

    static func parse(_ data: Data, repo: String) throws -> [AgentIssue] {
        struct Raw: Decodable {
            struct Label: Decodable { let name: String }
            struct Reference: Decodable { let url: URL }
            let number: Int, title: String, body: String?, url: URL, createdAt: Date, closedAt: Date?, state: String
            let labels: [Label]?, closedByPullRequestsReferences: [Reference]?
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode([Raw].self, from: data).map { raw in
            let pullRequest = raw.closedByPullRequestsReferences?.last?.url
            let status: Status = raw.state == "CLOSED" ? .done
                : pullRequest != nil ? .prOpen
                : (raw.labels ?? []).contains { $0.name == inProgressLabel } ? .inProgress : .open
            return AgentIssue(repo: repo, number: raw.number, title: raw.title, body: raw.body ?? "", url: raw.url,
                              created: raw.createdAt, closed: raw.closedAt, status: status, pullRequest: pullRequest)
        }
    }

    /// Body for issues created from the app, structured so an agent can work with it directly.
    static func body(task: String, criteria: String) -> String {
        var text = "## Aufgabe\n\n\(task.trimmingCharacters(in: .whitespacesAndNewlines))\n"
        let lines = criteria.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        if !lines.isEmpty {
            text += "\n## Akzeptanzkriterien\n\n" + lines.map { "- [ ] " + ($0.hasPrefix("- ") ? String($0.dropFirst(2)) : $0) }.joined(separator: "\n") + "\n"
        }
        return text + "\n---\n_Angelegt über To-Do List für Coding-Agents (Label `\(label)`). Vorgehen siehe AGENTS.md._\n"
    }
}

/// An open issue that needs attention soon (#26).
struct UrgentIssue: Identifiable, Equatable, Sendable {
    static let jsonFields = "number,title,url,labels,assignees,updatedAt"

    let repo: String
    let number: Int
    let title: String
    let url: URL
    let labels: [String]
    let assignees: [String]
    let updated: Date

    var id: String { "\(repo)#\(number)" }
    var isAgent: Bool { labels.contains(AgentIssue.label) }
    /// Priority and running number from a title like „[P1-03] …“; untagged issues sort last.
    var rank: (priority: Int, number: Int) {
        let parts = title.hasPrefix("[P") ? title.dropFirst(2).prefix { $0 != "]" }.split(separator: "-") : []
        guard parts.count == 2, let priority = Int(parts[0]), let running = Int(parts[1]) else { return (9, number) }
        return (priority, running)
    }

    /// Urgent means: title starts with „[P1“, labelled `dringend` or `P1`, or assigned to me.
    func isUrgent(for login: String?) -> Bool {
        title.hasPrefix("[P1") || labels.contains { ["dringend", "p1"].contains($0.lowercased()) }
            || (login.map(assignees.contains) ?? false)
    }

    static func parse(_ data: Data, repo: String) throws -> [UrgentIssue] {
        struct Raw: Decodable {
            struct Name: Decodable { let name: String }
            struct Login: Decodable { let login: String }
            let number: Int, title: String, url: URL, labels: [Name]?, assignees: [Login]?, updatedAt: Date
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode([Raw].self, from: data).map {
            UrgentIssue(repo: repo, number: $0.number, title: $0.title, url: $0.url, labels: ($0.labels ?? []).map(\.name),
                        assignees: ($0.assignees ?? []).map(\.login), updated: $0.updatedAt)
        }
    }
}

@MainActor final class DevStore: ObservableObject {
    enum Connection: Equatable {
        case unknown, connected(login: String), failed(GitHubError)
    }

    @Published private(set) var connection = Connection.unknown
    @Published private(set) var isRefreshing = false
    @Published private(set) var availableRepos: [String] = []
    @Published private(set) var lastUpdated: Date?
    /// nil means the default: every repository the user owns.
    @Published private(set) var chosenRepos: [String]?
    @Published private(set) var pullRequests: [PullRequest] = []
    /// Repositories whose pull requests could not be loaded in the last refresh.
    @Published private(set) var failedRepos: [String] = []
    @Published private(set) var agentIssues: [AgentIssue] = []
    @Published private(set) var openIssues: [UrgentIssue] = []

    private let defaults: UserDefaults
    private let locate: () -> GitHubCLI?

    init(defaults: UserDefaults = .standard, locate: @escaping () -> GitHubCLI? = { GitHubCLI.locate() }) {
        self.defaults = defaults
        self.locate = locate
        chosenRepos = defaults.stringArray(forKey: "devRepos")
        // Last successful result, shown with its timestamp until the next refresh finishes.
        if let cache = defaults.dictionary(forKey: "devCache"),
           let login = cache["login"] as? String, let repos = cache["repos"] as? [String], let updated = cache["updated"] as? Date {
            availableRepos = repos
            lastUpdated = updated
            connection = .connected(login: login)
        }
    }

    var login: String? {
        if case .connected(let login) = connection { return login }
        return nil
    }

    var selectedRepos: [String] {
        if let chosenRepos { return chosenRepos.filter(availableRepos.contains) }
        guard let login else { return [] }
        return availableRepos.filter { $0.hasPrefix(login + "/") }
    }

    func isSelected(_ repo: String) -> Bool { selectedRepos.contains(repo) }

    func setSelected(_ repo: String, _ selected: Bool) {
        var repos = selectedRepos.filter { $0 != repo }
        if selected { repos.append(repo) }
        chosenRepos = availableRepos.filter(repos.contains)
        defaults.set(chosenRepos, forKey: "devRepos")
    }

    func pullRequests(in category: PullRequest.Category) -> [PullRequest] {
        pullRequests.filter { selectedRepos.contains($0.repo) && $0.category(for: login) == category }
    }

    /// Merge commit, as agreed in #25; removes the pull request locally on success.
    func merge(_ pr: PullRequest) async throws {
        guard let cli = locate() else { throw GitHubError.missingCLI }
        _ = try await cli.run(["pr", "merge", String(pr.number), "-R", pr.repo, "--merge"], timeout: 60)
        pullRequests.removeAll { $0.id == pr.id }
    }

    func refresh() async {
        guard !isRefreshing else { return }
        guard let cli = locate() else { connection = .failed(.missingCLI); return }
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            let login = nonEmptyLines(try await cli.run(["api", "user", "--jq", ".login"])).first ?? ""
            let repos = nonEmptyLines(try await cli.run(["api", "--paginate", "user/repos?per_page=100&sort=pushed&affiliation=owner,collaborator,organization_member", "--jq", ".[].full_name"]))
            availableRepos = repos
            lastUpdated = Date()
            connection = .connected(login: login)
            await loadPullRequests(cli)
            await loadAgentIssues(cli)
            await loadOpenIssues(cli)
            defaults.set(["login": login, "repos": repos, "updated": lastUpdated!], forKey: "devCache")
        } catch let error as GitHubError {
            connection = .failed(error)
        } catch {
            connection = .failed(.failed(error.localizedDescription))
        }
    }

    /// Open agent issues plus those finished within the last week.
    var visibleAgentIssues: [AgentIssue] {
        let weekAgo = Date().addingTimeInterval(-7 * 86400)
        return agentIssues.filter { selectedRepos.contains($0.repo) && ($0.closed ?? .distantFuture) > weekAgo }
            .sorted { $0.status.rawValue != $1.status.rawValue ? $0.status.rawValue < $1.status.rawValue : $0.created > $1.created }
    }

    func createAgentIssue(repo: String, title: String, body: String) async throws {
        guard let cli = locate() else { throw GitHubError.missingCLI }
        // --force creates the label or leaves an existing one usable.
        _ = try await cli.run(["label", "create", AgentIssue.label, "-R", repo, "--color", "0E8A16", "--description", "Kann von einem Coding-Agent selbstständig abgearbeitet werden", "--force"])
        _ = try await cli.run(["issue", "create", "-R", repo, "--title", title, "--body", body, "--label", AgentIssue.label])
        await loadAgentIssues(cli)
    }

    func setInProgress(_ issue: AgentIssue, _ inProgress: Bool) async throws {
        guard let cli = locate() else { throw GitHubError.missingCLI }
        if inProgress {
            _ = try await cli.run(["label", "create", AgentIssue.inProgressLabel, "-R", issue.repo, "--color", "FBCA04", "--description", "Ein Agent arbeitet gerade daran", "--force"])
        }
        _ = try await cli.run(["issue", "edit", String(issue.number), "-R", issue.repo, inProgress ? "--add-label" : "--remove-label", AgentIssue.inProgressLabel])
        await loadAgentIssues(cli)
    }

    func removeAgentLabel(_ issue: AgentIssue) async throws {
        guard let cli = locate() else { throw GitHubError.missingCLI }
        _ = try await cli.run(["issue", "edit", String(issue.number), "-R", issue.repo, "--remove-label", AgentIssue.label])
        agentIssues.removeAll { $0.id == issue.id }
    }

    var urgentIssues: [UrgentIssue] {
        openIssues.filter { selectedRepos.contains($0.repo) && $0.isUrgent(for: login) }
            .sorted { $0.rank != $1.rank ? $0.rank < $1.rank : $0.repo < $1.repo }
    }

    /// Hands an existing issue to coding agents by adding the `agent` label (#27).
    func markAsAgent(_ issue: UrgentIssue) async throws {
        guard let cli = locate() else { throw GitHubError.missingCLI }
        _ = try await cli.run(["label", "create", AgentIssue.label, "-R", issue.repo, "--color", "0E8A16", "--description", "Kann von einem Coding-Agent selbstständig abgearbeitet werden", "--force"])
        _ = try await cli.run(["issue", "edit", String(issue.number), "-R", issue.repo, "--add-label", AgentIssue.label])
        await loadAgentIssues(cli)
        await loadOpenIssues(cli)
    }

    private func loadOpenIssues(_ cli: GitHubCLI) async {
        let repos = selectedRepos
        openIssues = await withTaskGroup(of: [UrgentIssue].self) { group in
            for repo in repos {
                group.addTask {
                    let data = try? await cli.run(["issue", "list", "-R", repo, "--state", "open", "--limit", "100", "--json", UrgentIssue.jsonFields])
                    return data.flatMap { try? UrgentIssue.parse($0, repo: repo) } ?? []
                }
            }
            var collected: [UrgentIssue] = []
            for await result in group { collected += result }
            return collected
        }
    }

    private func loadAgentIssues(_ cli: GitHubCLI) async {
        let repos = selectedRepos
        let results = await withTaskGroup(of: [AgentIssue].self) { group in
            for repo in repos {
                group.addTask {
                    let data = try? await cli.run(["issue", "list", "-R", repo, "--label", AgentIssue.label, "--state", "all", "--limit", "30", "--json", AgentIssue.jsonFields])
                    return data.flatMap { try? AgentIssue.parse($0, repo: repo) } ?? []
                }
            }
            var collected: [AgentIssue] = []
            for await result in group { collected += result }
            return collected
        }
        agentIssues = results
    }

    private func loadPullRequests(_ cli: GitHubCLI) async {
        let repos = selectedRepos
        let results = await withTaskGroup(of: (String, [PullRequest]?).self) { group in
            for repo in repos {
                group.addTask {
                    let data = try? await cli.run(["pr", "list", "-R", repo, "--state", "open", "--limit", "50", "--json", PullRequest.jsonFields])
                    return (repo, data.flatMap { try? PullRequest.parse($0, repo: repo) })
                }
            }
            var collected: [(String, [PullRequest]?)] = []
            for await result in group { collected.append(result) }
            return collected
        }
        failedRepos = results.filter { $0.1 == nil }.map(\.0).sorted()
        pullRequests = results.flatMap { $0.1 ?? [] }.sorted { $0.created > $1.created }
    }
}

/// Terminal script that starts Claude Code with an agent prompt (#79). The prompt is read from a private file,
/// so issue text never becomes part of the shell command.
enum ClaudeScript {
    static func make(folder: String, promptFile: String) -> String {
        """
        #!/bin/zsh -l
        cd \(quoted(folder)) || exit 1
        prompt=$(cat \(quoted(promptFile))); rm -f \(quoted(promptFile)) "$0"
        if ! command -v claude >/dev/null; then
          echo "Claude Code fehlt – installieren mit: npm install -g @anthropic-ai/claude-code"; exit 1
        fi
        exec claude "$prompt"

        """
    }

    static func quoted(_ text: String) -> String {
        "'" + text.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
