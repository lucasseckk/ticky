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
    /// Sample data that shows how the Dev section works; never sent to GitHub.
    var isExample = false

    var id: String { "\(repo)#\(number)" }

    static func examples(login: String) -> [PullRequest] {
        func pr(_ repo: String, _ number: Int, _ title: String, _ author: String, hoursAgo: Double, _ ci: CI, draft: Bool = false, review: Bool = false) -> PullRequest {
            PullRequest(repo: "beispiel/\(repo)", number: number, title: title, author: author, created: Date().addingTimeInterval(-hoursAgo * 3600),
                        isDraft: draft, url: URL(string: "https://github.com/\(login)")!, reviewRequests: review ? [login] : [], ci: ci, isExample: true)
        }
        return [
            pr("uni-app", 12, "Login-Seite überarbeiten", "anna", hoursAgo: 3, .success, review: true),
            pr("uni-app", 14, "Datenbank-Migration für Kurse", "max", hoursAgo: 26, .failure, review: true),
            pr("agent-tools", 7, "Agent liest Issues mit Label „agent“", "anna", hoursAgo: 1, .pending, review: true),
            pr("uni-app", 15, "Übungsblatt-Parser", login, hoursAgo: 5, .success),
            pr("agent-tools", 9, "Workflow für Agent-Issues", login, hoursAgo: 50, .none, draft: true),
            pr("uni-app", 11, "Abhängigkeiten aktualisieren", "dependabot", hoursAgo: 72, .success),
        ]
    }
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
    @Published var showsExamples: Bool { didSet { defaults.set(showsExamples, forKey: "devExamples") } }
    @Published private(set) var mergedExamples: Set<String> = []

    private let defaults: UserDefaults
    private let locate: () -> GitHubCLI?

    init(defaults: UserDefaults = .standard, locate: @escaping () -> GitHubCLI? = { GitHubCLI.locate() }) {
        self.defaults = defaults
        self.locate = locate
        chosenRepos = defaults.stringArray(forKey: "devRepos")
        showsExamples = defaults.object(forKey: "devExamples") as? Bool ?? true
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
        let examples = showsExamples ? login.map(PullRequest.examples).map { $0.filter { !mergedExamples.contains($0.id) } } ?? [] : []
        return (examples + pullRequests.filter { selectedRepos.contains($0.repo) }).filter { $0.category(for: login) == category }
    }

    /// Merge commit, as agreed in #25; removes the pull request locally on success.
    func merge(_ pr: PullRequest) async throws {
        if pr.isExample {
            try? await Task.sleep(for: .milliseconds(600))
            mergedExamples.insert(pr.id)
            return
        }
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
            defaults.set(["login": login, "repos": repos, "updated": lastUpdated!], forKey: "devCache")
        } catch let error as GitHubError {
            connection = .failed(error)
        } catch {
            connection = .failed(.failed(error.localizedDescription))
        }
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
