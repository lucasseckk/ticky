import SwiftUI
import AppKit

enum Priority: Int, Codable, CaseIterable, Identifiable, Sendable {
    case low, normal, high
    var id: Int { rawValue }
    var label: String { ["Niedrig", "Mittel", "Hoch"][rawValue] }
}

enum RepeatRule: String, Codable, CaseIterable, Identifiable, Sendable {
    case none, daily, weekly, monthly, custom
    var id: String { rawValue }
    var label: String {
        switch self {
        case .none: return "Nie"
        case .daily: return "Täglich"
        case .weekly: return "Wöchentlich"
        case .monthly: return "Monatlich"
        case .custom: return "Individuelle Tage"
        }
    }
}

enum Weekday: Int, Codable, CaseIterable, Hashable, Identifiable, Sendable {
    case monday = 2, tuesday, wednesday, thursday, friday, saturday, sunday
    var id: Int { rawValue }
    var shortLabel: String { ["", "", "Mo", "Di", "Mi", "Do", "Fr", "Sa", "So"][rawValue] }
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
        case .none: return "Keine Extra-Erinnerung"
        case .tenMinutes: return "10 Minuten vorher"
        case .thirtyMinutes: return "30 Minuten vorher"
        case .oneHour: return "1 Stunde vorher"
        case .oneDay: return "1 Tag vorher"
        case .twoDays: return "2 Tage vorher"
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

    /// Only finished one-off to-dos may be archived; a recurring one would silently stop coming back.
    var canArchive: Bool { done && repeatRule == .none }

    enum CodingKeys: String, CodingKey { case id, title, priority, due, repeatRule, repeatDays, groupID, customPriorityID, extraReminder, done, archived, created }
    init(title: String, priority: Priority = .normal, due: Date? = nil, repeatRule: RepeatRule = .none, repeatDays: Set<Weekday> = [], groupID: UUID? = nil, customPriorityID: UUID? = nil, extraReminder: ReminderOffset = .none, done: Bool = false, created: Date = Date()) {
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
        case .open: return "Offen"
        case .done: return "Erledigt"
        case .all: return "Alle"
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
        case .all: return "Alle"
        case .overdue: return "Überfällig"
        case .today: return "Heute"
        case .nextSevenDays: return "Nächste 7 Tage"
        case .none: return "Ohne Datum"
        }
    }
}

enum DueBucket: Int, CaseIterable, Identifiable, Sendable {
    case overdue, today, tomorrow, thisWeek, later, none, past
    var id: Int { rawValue }
    var label: String {
        switch self {
        case .overdue: return "Überfällig"
        case .today: return "Heute"
        case .tomorrow: return "Morgen"
        case .thisWeek: return "Diese Woche"
        case .later: return "Später"
        case .none: return "Ohne Datum"
        case .past: return "Vergangen"
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
        let newDirectory = support.appendingPathComponent("todo list")
        let oldDirectory = support.appendingPathComponent("KleineListe")
        if file == nil, !FileManager.default.fileExists(atPath: newDirectory.path), FileManager.default.fileExists(atPath: oldDirectory.path) {
            try? FileManager.default.moveItem(at: oldDirectory, to: newDirectory)
        }
        self.file = file ?? newDirectory.appendingPathComponent("todos.json")
        self.groupsFile = self.file.deletingLastPathComponent().appendingPathComponent("groups.json")
        self.prioritiesFile = self.file.deletingLastPathComponent().appendingPathComponent("custom-priorities.json")
        do { todos = try JSONDecoder().decode([Todo].self, from: Data(contentsOf: self.file)) }
        catch let e as CocoaError where e.code == .fileReadNoSuchFile { }
        catch { writable = false; self.error = "Aufgaben konnten nicht geladen werden. Die Datei bleibt erhalten. \(error.localizedDescription)" }
        if let data = try? Data(contentsOf: groupsFile) { groups = (try? JSONDecoder().decode([TodoGroup].self, from: data)) ?? [] }
        if let data = try? Data(contentsOf: prioritiesFile) { customPriorities = (try? JSONDecoder().decode([CustomPriority].self, from: data)) ?? [] }
    }
    var count: Int { todos.filter { !$0.done }.count }
    func save(_ item: Todo) {
        guard writable else { return }
        var item = item
        item.title = item.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !item.title.isEmpty else { return }
        if let i = todos.firstIndex(where: { $0.id == item.id }) { todos[i] = item }
        else { todos.append(item) }
        persist()
    }
    func toggle(_ item: Todo) {
        guard writable, var changed = todos.first(where: { $0.id == item.id }) else { return }
        recordUndo(changed.done ? "„\(changed.title)“ wieder geöffnet" : "„\(changed.title)“ erledigt")
        changed.done.toggle()
        if !changed.done { changed.archived = false }
        save(changed)
    }
    func moveTodo(_ id: UUID, to groupID: UUID?) {
        guard writable, let index = todos.firstIndex(where: { $0.id == id }) else { return }
        recordUndo("„\(todos[index].title)“ verschoben")
        todos[index].groupID = groupID
        persist()
    }
    /// Moves a to-do to the target's position (after it when moving down, before it when moving up) and into the target's group.
    func reorderTodo(_ id: UUID, to targetID: UUID) {
        guard writable, id != targetID,
              let from = todos.firstIndex(where: { $0.id == id }),
              let to = todos.firstIndex(where: { $0.id == targetID }) else { return }
        recordUndo("„\(todos[from].title)“ verschoben")
        var item = todos.remove(at: from)
        item.groupID = todos[to > from ? to - 1 : to].groupID
        todos.insert(item, at: to)
        persist()
    }
    func reorderGroup(_ id: UUID, to targetID: UUID) {
        guard writable, id != targetID,
              let from = groups.firstIndex(where: { $0.id == id }),
              let to = groups.firstIndex(where: { $0.id == targetID }) else { return }
        recordUndo("Gruppe „\(groups[from].name)“ verschoben")
        groups.insert(groups.remove(at: from), at: to)
        persistGroups()
    }
    func delete(_ item: Todo) {
        guard writable, todos.contains(where: { $0.id == item.id }) else { return }
        recordUndo("„\(item.title)“ gelöscht")
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
        recordUndo("Gruppe „\(group.name)“ gelöscht")
        groups.removeAll { $0.id == group.id }
        todos = todos.map { var todo = $0; if todo.groupID == group.id { todo.groupID = nil }; return todo }
        persistGroups(); persist()
    }
    func deleteCustomPriority(_ priority: CustomPriority) {
        guard writable else { return }
        recordUndo("Priorität „\(priority.name)“ gelöscht")
        customPriorities.removeAll { $0.id == priority.id }
        todos = todos.map { var todo = $0; if todo.customPriorityID == priority.id { todo.customPriorityID = nil }; return todo }
        persistPriorities(); persist()
    }
    var archivableCount: Int { todos.filter { $0.canArchive && !$0.archived }.count }
    func archiveDone() {
        guard writable, archivableCount > 0 else { return }
        recordUndo("\(archivableCount) erledigte archiviert")
        todos = todos.map { var todo = $0; if todo.canArchive { todo.archived = true }; return todo }
        persist()
    }
    func setArchived(_ id: UUID, _ archived: Bool) {
        guard writable, let index = todos.firstIndex(where: { $0.id == id }), !archived || todos[index].canArchive else { return }
        recordUndo(archived ? "„\(todos[index].title)“ archiviert" : "„\(todos[index].title)“ wiederhergestellt")
        todos[index].archived = archived
        persist()
    }
    func clearArchive() {
        guard writable, todos.contains(where: \.archived) else { return }
        recordUndo("Archiv geleert")
        todos.removeAll(where: \.archived)
        persist()
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
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(todos).write(to: file, options: .atomic)
            error = nil
        } catch { self.error = "Speichern fehlgeschlagen. Änderungen sind vorerst nur im Arbeitsspeicher. \(error.localizedDescription)" }
    }
    private func persistGroups() {
        do {
            try FileManager.default.createDirectory(at: groupsFile.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(groups).write(to: groupsFile, options: .atomic)
        } catch let saveError { self.error = "Gruppen konnten nicht gespeichert werden. \(saveError.localizedDescription)" }
    }
    private func persistPriorities() {
        do {
            try FileManager.default.createDirectory(at: prioritiesFile.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(customPriorities).write(to: prioritiesFile, options: .atomic)
        } catch let saveError { self.error = "Custom-Prioritäten konnten nicht gespeichert werden. \(saveError.localizedDescription)" }
    }
}
