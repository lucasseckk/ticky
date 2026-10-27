import Foundation

@main struct StoreCheck {
    @MainActor static func main() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("todos.json")
        let store = Store(file: file)
        precondition(store.error == nil)
        store.save(Todo(title: "  Lernen  ", priority: .high, due: Date(timeIntervalSince1970: 2000000000), extraReminder: .oneHour))
        let loaded = Store(file: file)
        precondition(loaded.error == nil)
        precondition(loaded.todos.first?.title == "Lernen")
        precondition(loaded.todos.first?.priority == .high)
        precondition(loaded.todos.first?.due == Date(timeIntervalSince1970: 2000000000))
        precondition(loaded.todos.first?.extraReminder == .oneHour)
        loaded.createGroup(name: "Arbeit")
        loaded.createCustomPriority(name: "Kritisch", threatLevel: 5)
        precondition(Store(file: file).groups.first?.name == "Arbeit")
        precondition(Store(file: file).customPriorities.first?.threatLevel == 5)
        let item = loaded.todos[0]
        let groupID = loaded.groups[0].id
        loaded.moveTodo(item.id, to: groupID)
        precondition(Store(file: file).todos.first?.groupID == groupID)
        loaded.toggle(item)
        precondition(Store(file: file).count == 0)
        precondition(Store(file: file).todos.first?.groupID == groupID)
        loaded.moveTodo(item.id, to: nil)
        precondition(Store(file: file).todos.first?.groupID == nil)
        loaded.moveTodo(item.id, to: groupID)
        precondition(Store(file: file).todos.count == 1)
        loaded.delete(item)
        precondition(Store(file: file).todos.isEmpty)
        let original = Data("unlesbare Daten".utf8)
        try original.write(to: file)
        let corrupt = Store(file: file)
        precondition(corrupt.error != nil)
        corrupt.save(Todo(title: "Test"))
        let preserved = try Data(contentsOf: file)
        precondition(preserved == original)
        print("OK: Speichern, Laden, Priorität, Fälligkeit, Abhaken, Gruppen verschieben, Löschen, Schutz beschädigter Daten")
    }
}
