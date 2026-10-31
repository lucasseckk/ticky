import SwiftUI
import AppKit

enum Priority: Int, Codable, CaseIterable, Identifiable, Sendable {
    case low, normal, high
    var id: Int { rawValue }
    var label: String { [String(localized: "Niedrig"), String(localized: "Mittel"), String(localized: "Hoch")][rawValue] }
}

enum RepeatRule: String, Codable, CaseIterable, Identifiable, Sendable {
    case none, daily, weekly, monthly, custom
    var id: String { rawValue }
    var label: String {
        switch self {
        case .none: return String(localized: "Nie")
        case .daily: return String(localized: "Täglich")
        case .weekly: return String(localized: "Wöchentlich")
        case .monthly: return String(localized: "Monatlich")
        case .custom: return String(localized: "Individuelle Tage")
        }
    }
}

enum Weekday: Int, Codable, CaseIterable, Hashable, Identifiable, Sendable {
    case monday = 2, tuesday, wednesday, thursday, friday, saturday, sunday
    var id: Int { rawValue }
    var shortLabel: String { ["", "", String(localized: "Mo"), String(localized: "Di"), String(localized: "Mi"), String(localized: "Do"), String(localized: "Fr"), String(localized: "Sa"), String(localized: "So")][rawValue] }
    /// Calendar counts Sunday as 1; the stored raw value 8 must stay for existing data.
    var calendarWeekday: Int { self == .sunday ? 1 : rawValue }
}

extension RepeatRule {
    /// The next occurrence strictly after `date`, keeping the time of day. nil for `.none`.
    func next(after date: Date, days: Set<Weekday>, calendar: Calendar = .current) -> Date? {
        switch self {
        case .none: return nil
        case .daily: return calendar.date(byAdding: .day, value: 1, to: date)
        case .weekly: return calendar.date(byAdding: .day, value: 7, to: date)
        case .monthly: return calendar.date(byAdding: .month, value: 1, to: date)
        case .custom:
            let weekdays = Set(days.map(\.calendarWeekday))
            guard !weekdays.isEmpty else { return calendar.date(byAdding: .day, value: 7, to: date) }
            return (1...7).lazy.compactMap { calendar.date(byAdding: .day, value: $0, to: date) }
                .first { weekdays.contains(calendar.component(.weekday, from: $0)) }
        }
    }
}

enum ReminderOffset: Int, Codable, CaseIterable, Identifiable, Sendable {
    case none = 0
    case tenMinutes = 10
    case thirtyMinutes = 30
    case oneHour = 60
    case oneDay = 1440
    case twoDays = 2880

    var id: Int { rawValue }
    var label: String {
        switch self {
        case .none: return String(localized: "Keine Extra-Erinnerung")
        case .tenMinutes: return String(localized: "10 Minuten vorher")
        case .thirtyMinutes: return String(localized: "30 Minuten vorher")
        case .oneHour: return String(localized: "1 Stunde vorher")
        case .oneDay: return String(localized: "1 Tag vorher")
        case .twoDays: return String(localized: "2 Tage vorher")
        }
    }
}

struct TodoGroup: Identifiable, Codable, Hashable, Sendable {
    var id = UUID()
    var name: String
    var notes = ""
    var colorHex = "#6C5CE7"

    enum CodingKeys: String, CodingKey { case id, name, notes, colorHex }
    init(id: UUID = UUID(), name: String, notes: String = "", colorHex: String = "#6C5CE7") {
        self.id = id
        self.name = name
        self.notes = notes
        self.colorHex = colorHex
    }
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        notes = try container.decodeIfPresent(String.self, forKey: .notes) ?? ""
        colorHex = try container.decodeIfPresent(String.self, forKey: .colorHex) ?? "#6C5CE7"
    }
}

struct CustomPriority: Identifiable, Codable, Hashable, Sendable {
    var id = UUID()
    var name: String
    var threatLevel: Int = 3
    var colorHex: String = "#94BD80"
}

struct Todo: Identifiable, Codable, Sendable {
    var id = UUID()
    var title: String
    var priority: Priority = .normal
    var due: Date?
    var repeatRule: RepeatRule = .none
    var repeatDays: Set<Weekday> = []
    var groupID: UUID?
    var customPriorityID: UUID?
    var extraReminder: ReminderOffset = .none
    var done = false
    var archived = false
    var created = Date()
    /// Dev to-dos live only in the Dev section (#49), not in the normal list.
    var isDev = false
    /// For example the pull request a dev to-do was created from.
    var link: URL?
    /// A reminder pushed back from a notification (#9); survives restarts.
    var snoozedUntil: Date?

    /// Only finished one-off to-dos may be archived; a recurring one would silently stop coming back.
    var canArchive: Bool { done && repeatRule == .none && !isDev }
    /// The archive shows every finished one-off to-do, explicitly archived or not.
    var showsInArchive: Bool { archived || canArchive }

    enum CodingKeys: String, CodingKey { case id, title, priority, due, repeatRule, repeatDays, groupID, customPriorityID, extraReminder, done, archived, created, isDev, link, snoozedUntil }
    init(title: String, priority: Priority = .normal, due: Date? = nil, repeatRule: RepeatRule = .none, repeatDays: Set<Weekday> = [], groupID: UUID? = nil, customPriorityID: UUID? = nil, extraReminder: ReminderOffset = .none, done: Bool = false, created: Date = Date(), isDev: Bool = false, link: URL? = nil) {
        self.title = title
        self.priority = priority
        self.due = due
        self.repeatRule = repeatRule
        self.repeatDays = repeatDays
        self.groupID = groupID
        self.customPriorityID = customPriorityID
        self.extraReminder = extraReminder
        self.done = done
        self.created = created
        self.isDev = isDev
        self.link = link
    }
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        priority = try container.decode(Priority.self, forKey: .priority)
        due = try container.decodeIfPresent(Date.self, forKey: .due)
        repeatRule = try container.decodeIfPresent(RepeatRule.self, forKey: .repeatRule) ?? .none
        repeatDays = try container.decodeIfPresent(Set<Weekday>.self, forKey: .repeatDays) ?? []
        groupID = try container.decodeIfPresent(UUID.self, forKey: .groupID)
        customPriorityID = try container.decodeIfPresent(UUID.self, forKey: .customPriorityID)
        extraReminder = try container.decodeIfPresent(ReminderOffset.self, forKey: .extraReminder) ?? .none
        done = try container.decode(Bool.self, forKey: .done)
        archived = try container.decodeIfPresent(Bool.self, forKey: .archived) ?? false
        created = try container.decode(Date.self, forKey: .created)
        isDev = try container.decodeIfPresent(Bool.self, forKey: .isDev) ?? false
        link = try container.decodeIfPresent(URL.self, forKey: .link)
        snoozedUntil = try container.decodeIfPresent(Date.self, forKey: .snoozedUntil)
    }
}
enum PriorityChoice: Hashable, Sendable {
    case standard(Priority)
    case custom(UUID)
}

enum StatusFilter: String, CaseIterable, Identifiable, Sendable {
    case open, done, all
    var id: String { rawValue }
    var label: String {
        switch self {
        case .open: return String(localized: "Offen")
        case .done: return String(localized: "Erledigt")
        case .all: return String(localized: "Alle")
        }
    }
}

enum GroupFilter: Hashable, Sendable {
    case all, ungrouped, group(UUID)
}

enum DueFilter: String, CaseIterable, Identifiable, Sendable {
    case all, overdue, today, nextSevenDays, none
    var id: String { rawValue }
    var label: String {
        switch self {
        case .all: return String(localized: "Alle")
        case .overdue: return String(localized: "Überfällig")
        case .today: return String(localized: "Heute")
        case .nextSevenDays: return String(localized: "Nächste 7 Tage")
        case .none: return String(localized: "Ohne Datum")
        }
    }
}

enum DueBucket: Int, CaseIterable, Identifiable, Sendable {
    case overdue, today, tomorrow, thisWeek, later, none, past
    var id: Int { rawValue }
    var label: String {
        switch self {
        case .overdue: return String(localized: "Überfällig")
        case .today: return String(localized: "Heute")
        case .tomorrow: return String(localized: "Morgen")
        case .thisWeek: return String(localized: "Diese Woche")
        case .later: return String(localized: "Später")
        case .none: return String(localized: "Ohne Datum")
        case .past: return String(localized: "Vergangen")
        }
    }

    /// Uses the calendar's local time zone; done to-dos are never overdue, only past.
    init(_ todo: Todo, now: Date = Date(), calendar: Calendar = .current) {
        guard let due = todo.due else { self = .none; return }
        let sameDay = calendar.isDate(due, inSameDayAs: now)
        if due < now, !(todo.done && sameDay) {
            self = todo.done ? .past : .overdue
        } else if sameDay {
            self = .today
        } else if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now), calendar.isDate(due, inSameDayAs: tomorrow) {
            self = .tomorrow
        } else if calendar.isDate(due, equalTo: now, toGranularity: .weekOfYear) {
            self = .thisWeek
        } else {
            self = .later
        }
    }
}

struct TodoFilter: Equatable, Sendable {
    var query = ""
    var group: GroupFilter = .all
    var priority: PriorityChoice?
    var due: DueFilter = .all
    var isActive: Bool { self != TodoFilter() }

    func matches(_ todo: Todo, now: Date = Date(), calendar: Calendar = .current) -> Bool {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if !query.isEmpty, !todo.title.localizedCaseInsensitiveContains(query) { return false }
        switch group {
        case .all: break
        case .ungrouped: if todo.groupID != nil { return false }
        case .group(let id): if todo.groupID != id { return false }
        }
        switch priority {
        case nil: break
        case .standard(let level): if todo.customPriorityID != nil || todo.priority != level { return false }
        case .custom(let id): if todo.customPriorityID != id { return false }
        }
        switch due {
        case .all: return true
        case .none: return todo.due == nil
        case .overdue: return !todo.done && (todo.due.map { $0 < now } ?? false)
        case .today: return todo.due.map { calendar.isDate($0, inSameDayAs: now) } ?? false
        case .nextSevenDays: return todo.due.map { $0 >= now && $0 < now.addingTimeInterval(7 * 86400) } ?? false
        }
    }
}

/// Versioned export format; group notes travel inside the groups.
struct BackupFile: Codable {
    static let currentVersion = 1
    var version = BackupFile.currentVersion
    var exportedAt = Date()
    var todos: [Todo]
    var groups: [TodoGroup]
    var customPriorities: [CustomPriority]

    static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
    static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

enum ImportError: LocalizedError {
    case unreadable, unsupportedVersion(Int), duplicateIDs
    var errorDescription: String? {
        switch self {
        case .unreadable: return String(localized: "Die Datei ist keine gültige Ticky-Sicherung.")
        case .unsupportedVersion(let version): return String(localized: "Sicherungsformat \(version) wird nicht unterstützt.")
        case .duplicateIDs: return String(localized: "Die Sicherung enthält doppelte Einträge.")
        }
    }
}

/// Snapshot taken before a change that can be undone; lives only in memory so no stale step survives a restart.
struct UndoStep: Identifiable {
    let id = UUID()
    let label: String
    let todos: [Todo]
    let groups: [TodoGroup]
    let customPriorities: [CustomPriority]
}

@MainActor final class Store: ObservableObject {
    @Published private(set) var todos: [Todo] = []
    @Published private(set) var groups: [TodoGroup] = []
    @Published private(set) var customPriorities: [CustomPriority] = []
    @Published private(set) var undoStep: UndoStep?
    @Published var error: String?
    private var writable = true
    private let file: URL
    private let groupsFile: URL
    private let prioritiesFile: URL
    init(file: URL? = nil) {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        // The app was renamed KleineListe → todo list → Ticky (#93); data moves along once.
        let newDirectory = support.appendingPathComponent("Ticky")
        let oldDirectory = ["todo list", "KleineListe"].map { support.appendingPathComponent($0) }.first { FileManager.default.fileExists(atPath: $0.path) }
        if file == nil, !FileManager.default.fileExists(atPath: newDirectory.path), let oldDirectory {
            try? FileManager.default.moveItem(at: oldDirectory, to: newDirectory)
        }
        self.file = file ?? newDirectory.appendingPathComponent("todos.json")
        self.groupsFile = self.file.deletingLastPathComponent().appendingPathComponent("groups.json")
        self.prioritiesFile = self.file.deletingLastPathComponent().appendingPathComponent("custom-priorities.json")
        todos = load(self.file)
        groups = load(groupsFile)
        customPriorities = load(prioritiesFile)
    }
    /// A missing file starts empty; an unreadable one stops all saving, so it is never overwritten (#126).
    private func load<Item: Decodable>(_ url: URL) -> [Item] {
        do { return try JSONDecoder().decode([Item].self, from: Data(contentsOf: url)) }
        catch let e as CocoaError where e.code == .fileReadNoSuchFile { return [] }
        catch {
            writable = false
            let message = String(localized: "\(url.lastPathComponent) konnte nicht gelesen werden und bleibt unverändert erhalten. Bis zur Reparatur wird nichts gespeichert. \(error.localizedDescription)")
            self.error = [self.error, message].compactMap { $0 }.joined(separator: "\n")
            return []
        }
    }
    var count: Int { todos.filter { !$0.done && !$0.isDev }.count }
    var overdueCount: Int { openTodos.filter { $0.due.map { $0 < Date() } ?? false }.count }
    /// Open, non-archived, non-dev to-dos; counted in the panel header.
    var openTodos: [Todo] { todos.filter { !$0.done && !$0.archived && !$0.isDev } }
    func save(_ item: Todo) {
        guard writable else { return }
        var item = item
        item.title = item.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !item.title.isEmpty else { return }
        if let i = todos.firstIndex(where: { $0.id == item.id }) { todos[i] = item }
        else { todos.append(item) }
        persist()
    }
    /// Marks an open to-do as done, e.g. from a notification action; does nothing if it is already done or gone.
    func finish(_ id: UUID) {
        guard let todo = todos.first(where: { $0.id == id }), !todo.done else { return }
        toggle(todo)
    }
    func snooze(_ id: UUID, until date: Date) {
        guard writable, var todo = todos.first(where: { $0.id == id }) else { return }
        todo.snoozedUntil = date
        save(todo)
    }
    func toggle(_ item: Todo, now: Date = Date(), calendar: Calendar = .current) {
        guard writable, var changed = todos.first(where: { $0.id == item.id }) else { return }
        // A recurring to-do with a date moves on to its next future date instead of staying done (#13).
        if !changed.done, let due = changed.due, var next = changed.repeatRule.next(after: due, days: changed.repeatDays, calendar: calendar) {
            while next <= now, let later = changed.repeatRule.next(after: next, days: changed.repeatDays, calendar: calendar) { next = later }
            recordUndo(String(localized: "„\(changed.title)“ erledigt – nächster Termin \(next.formatted(.dateTime.weekday(.abbreviated).day().month()))"))
            changed.due = next
            changed.snoozedUntil = nil
            save(changed)
            return
        }
        recordUndo(changed.done ? String(localized: "„\(changed.title)“ wieder geöffnet") : String(localized: "„\(changed.title)“ erledigt"))
        changed.done.toggle()
        if !changed.done { changed.archived = false }
        save(changed)
    }
    func moveTodo(_ id: UUID, to groupID: UUID?) {
        guard writable, let index = todos.firstIndex(where: { $0.id == id }) else { return }
        recordUndo(String(localized: "„\(todos[index].title)“ verschoben"))
        todos[index].groupID = groupID
        persist()
    }
    /// Moves a to-do to the target's position (after it when moving down, before it when moving up) and into the target's group.
    func reorderTodo(_ id: UUID, to targetID: UUID) {
        guard writable, id != targetID,
              let from = todos.firstIndex(where: { $0.id == id }),
              let to = todos.firstIndex(where: { $0.id == targetID }) else { return }
        recordUndo(String(localized: "„\(todos[from].title)“ verschoben"))
        var item = todos.remove(at: from)
        item.groupID = todos[to > from ? to - 1 : to].groupID
        todos.insert(item, at: to)
        persist()
    }
    func reorderGroup(_ id: UUID, to targetID: UUID) {
        guard writable, id != targetID,
              let from = groups.firstIndex(where: { $0.id == id }),
              let to = groups.firstIndex(where: { $0.id == targetID }) else { return }
        recordUndo(String(localized: "Gruppe „\(groups[from].name)“ verschoben"))
        groups.insert(groups.remove(at: from), at: to)
        persistGroups()
    }
    func delete(_ item: Todo) {
        guard writable, todos.contains(where: { $0.id == item.id }) else { return }
        recordUndo(String(localized: "„\(item.title)“ gelöscht"))
        todos.removeAll { $0.id == item.id }; persist()
    }
    func createGroup(name: String) {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard writable, !name.isEmpty else { return }
        groups.append(TodoGroup(name: name)); persistGroups()
    }
    func updateGroup(_ group: TodoGroup) {
        guard writable, let index = groups.firstIndex(where: { $0.id == group.id }) else { return }
        groups[index] = group; persistGroups()
    }
    func createCustomPriority(name: String, threatLevel: Int = 3) {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard writable, !name.isEmpty else { return }
        customPriorities.append(CustomPriority(name: name, threatLevel: min(max(threatLevel, 1), 5))); persistPriorities()
    }
    func deleteGroup(_ group: TodoGroup) {
        guard writable else { return }
        recordUndo(String(localized: "Gruppe „\(group.name)“ gelöscht"))
        groups.removeAll { $0.id == group.id }
        todos = todos.map { var todo = $0; if todo.groupID == group.id { todo.groupID = nil }; return todo }
        persistGroups(); persist()
    }
    func deleteCustomPriority(_ priority: CustomPriority) {
        guard writable else { return }
        recordUndo(String(localized: "Priorität „\(priority.name)“ gelöscht"))
        customPriorities.removeAll { $0.id == priority.id }
        todos = todos.map { var todo = $0; if todo.customPriorityID == priority.id { todo.customPriorityID = nil }; return todo }
        persistPriorities(); persist()
    }
    var archivableCount: Int { todos.filter { $0.canArchive && !$0.archived }.count }
    func archiveDone() {
        guard writable, archivableCount > 0 else { return }
        recordUndo(String(localized: "\(archivableCount) erledigte archiviert"))
        todos = todos.map { var todo = $0; if todo.canArchive { todo.archived = true }; return todo }
        persist()
    }
    func setArchived(_ id: UUID, _ archived: Bool) {
        guard writable, let index = todos.firstIndex(where: { $0.id == id }), !archived || todos[index].canArchive else { return }
        recordUndo(archived ? String(localized: "„\(todos[index].title)“ archiviert") : String(localized: "„\(todos[index].title)“ wiederhergestellt"))
        todos[index].archived = archived
        persist()
    }
    func clearArchive() {
        guard writable, todos.contains(where: \.showsInArchive) else { return }
        recordUndo(String(localized: "Archiv geleert"))
        todos.removeAll(where: \.showsInArchive)
        persist()
    }
    /// Finished dev to-dos form the Dev archive (#121).
    func clearDevArchive() {
        guard writable, todos.contains(where: { $0.isDev && $0.done }) else { return }
        recordUndo(String(localized: "Dev-Archiv geleert"))
        todos.removeAll { $0.isDev && $0.done }
        persist()
    }
    func exportData() throws -> Data {
        try BackupFile.encoder().encode(BackupFile(todos: todos, groups: groups, customPriorities: customPriorities))
    }
    /// Validates everything before touching current data, then saves the current state to Backups/ and replaces it.
    @discardableResult func importData(_ data: Data) throws -> URL {
        guard let backup = try? BackupFile.decoder().decode(BackupFile.self, from: data) else { throw ImportError.unreadable }
        guard backup.version == BackupFile.currentVersion else { throw ImportError.unsupportedVersion(backup.version) }
        guard Set(backup.todos.map(\.id)).count == backup.todos.count,
              Set(backup.groups.map(\.id)).count == backup.groups.count,
              Set(backup.customPriorities.map(\.id)).count == backup.customPriorities.count else { throw ImportError.duplicateIDs }
        guard writable else { throw CocoaError(.fileWriteNoPermission) }
        let directory = file.deletingLastPathComponent().appendingPathComponent("Backups")
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let safety = directory.appendingPathComponent("vor-import-\(stamp).json")
        try writePrivately(exportData(), to: safety)
        let groupIDs = Set(backup.groups.map(\.id)), priorityIDs = Set(backup.customPriorities.map(\.id))
        recordUndo(String(localized: "Sicherung importiert"))
        todos = backup.todos.map { todo in
            var todo = todo
            if let id = todo.groupID, !groupIDs.contains(id) { todo.groupID = nil }
            if let id = todo.customPriorityID, !priorityIDs.contains(id) { todo.customPriorityID = nil }
            return todo
        }
        groups = backup.groups
        customPriorities = backup.customPriorities
        persist(); persistGroups(); persistPriorities()
        return safety
    }
    func undo() {
        guard writable, let step = undoStep else { return }
        todos = step.todos; groups = step.groups; customPriorities = step.customPriorities
        undoStep = nil
        persist(); persistGroups(); persistPriorities()
    }
    func dismissUndo(_ id: UUID) {
        if undoStep?.id == id { undoStep = nil }
    }
    private func recordUndo(_ label: String) {
        undoStep = UndoStep(label: label, todos: todos, groups: groups, customPriorities: customPriorities)
    }
    func updateCustomPriority(_ priority: CustomPriority) {
        guard writable, let index = customPriorities.firstIndex(where: { $0.id == priority.id }) else { return }
        customPriorities[index] = priority; persistPriorities()
    }
    private func persist() {
        do {
            try writePrivately(JSONEncoder().encode(todos), to: file)
            error = nil
        } catch { self.error = String(localized: "Speichern fehlgeschlagen. Änderungen sind vorerst nur im Arbeitsspeicher. \(error.localizedDescription)") }
    }
    private func persistGroups() {
        do {
            try writePrivately(JSONEncoder().encode(groups), to: groupsFile)
        } catch let saveError { self.error = String(localized: "Gruppen konnten nicht gespeichert werden. \(saveError.localizedDescription)") }
    }
    private func persistPriorities() {
        do {
            try writePrivately(JSONEncoder().encode(customPriorities), to: prioritiesFile)
        } catch let saveError { self.error = String(localized: "Custom-Prioritäten konnten nicht gespeichert werden. \(saveError.localizedDescription)") }
    }
}

/// Snooze choices offered on a notification (#9).
enum Snooze: String, CaseIterable, Sendable {
    case tenMinutes, oneHour, tomorrow

    var label: String {
        switch self {
        case .tenMinutes: return String(localized: "10 Minuten")
        case .oneHour: return String(localized: "1 Stunde")
        case .tomorrow: return String(localized: "Morgen 9:00")
        }
    }

    func date(from now: Date, calendar: Calendar = .current) -> Date {
        switch self {
        case .tenMinutes: return now.addingTimeInterval(600)
        case .oneHour: return now.addingTimeInterval(3600)
        case .tomorrow:
            let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now))!
            return calendar.date(bySettingHour: 9, minute: 0, second: 0, of: tomorrow)!
        }
    }
}

/// Writes atomically and readable only by the current user: folder 0700, file 0600.
/// Encryption at rest is left to FileVault (see README, „Sicherheitsgrenzen“).
func writePrivately(_ data: Data, to url: URL) throws {
    let manager = FileManager.default
    let directory = url.deletingLastPathComponent()
    try manager.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
    try manager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
    try data.write(to: url, options: .atomic)
    try manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
}
