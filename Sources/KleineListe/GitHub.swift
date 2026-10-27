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

    func refreshIfStale(maxAge: TimeInterval = 300) async {
        if let lastUpdated, Date().timeIntervalSince(lastUpdated) < maxAge, login != nil { return }
        await refresh()
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
            defaults.set(["login": login, "repos": repos, "updated": lastUpdated!], forKey: "devCache")
        } catch let error as GitHubError {
            connection = .failed(error)
        } catch {
            connection = .failed(.failed(error.localizedDescription))
        }
    }
}
