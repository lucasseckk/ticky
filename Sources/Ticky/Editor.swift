import SwiftUI
import AppKit

struct Editor: View {
    @State var todo: Todo
    let isNew: Bool
    let groups: [TodoGroup]
    let customPriorities: [CustomPriority]
    @State private var priorityChoice: PriorityChoice = .standard(.normal)
    @State private var hasDue = false
    @State private var date = Date().addingTimeInterval(3600)
    let onSave: (Todo) -> Void
    let onCancel: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                IslandIconButton(systemImage: "arrow.left", label: String(localized: "Abbrechen"), action: onCancel)
                Text(isNew ? String(localized: "Neues To-Do") : String(localized: "To-Do bearbeiten")).font(.headline)
            }
            TextField("Titel", text: $todo.title)
                .textFieldStyle(.plain)
                .font(.title3.weight(.medium))
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .islandCapsule()
            VStack(alignment: .leading, spacing: 12) {
            Picker("Priorität", selection: $priorityChoice) {
                Section("Standard") {
                    ForEach(Priority.allCases) { priority in
                        Text(priority.label).tag(PriorityChoice.standard(priority))
                    }
                }
                if !customPriorities.isEmpty {
                    Section("Custom") {
                        ForEach(customPriorities) { priority in
                            Text(priority.name).tag(PriorityChoice.custom(priority.id))
                        }
                    }
                }
            }
            Picker("Gruppe", selection: Binding<UUID?>(get: { todo.groupID }, set: { todo.groupID = $0 })) {
                Text("Keine Gruppe").tag(Optional<UUID>.none)
                ForEach(groups) { group in
                    Text(group.name).tag(Optional(group.id))
                }
            }
            Toggle("Ablaufdatum", isOn: $hasDue)
            if hasDue { DatePicker("Datum", selection: $date).labelsHidden() }
            if hasDue {
                Picker("Extra-Erinnerung", selection: $todo.extraReminder) {
                    ForEach(ReminderOffset.allCases) { reminder in
                        Text(reminder.label).tag(reminder)
                    }
                }
            }
            Picker("Wiederholung", selection: $todo.repeatRule) {
                ForEach(RepeatRule.allCases) { Text($0.label).tag($0) }
            }
            if todo.repeatRule == .custom {
                HStack(spacing: 6) {
                    ForEach(Weekday.allCases) { day in
                        Button(day.shortLabel) {
                            if todo.repeatDays.contains(day) {
                                todo.repeatDays.remove(day)
                            } else {
                                todo.repeatDays.insert(day)
                            }
                        }
                        .buttonStyle(.plain)
                        .frame(width: 34, height: 28)
                        .background(todo.repeatDays.contains(day) ? Color.white : Color.white.opacity(0.1), in: Capsule())
                        .foregroundStyle(todo.repeatDays.contains(day) ? .black : .primary)
                        .accessibilityLabel("\(day.shortLabel) \(todo.repeatDays.contains(day) ? "ausgewählt" : "nicht ausgewählt")")
                    }
                }
            }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .islandSurface(cornerRadius: 18)
            HStack {
                Button("Abbrechen", action: onCancel).buttonStyle(.plain).foregroundStyle(.secondary)
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button {
                    todo.due = hasDue ? date : nil
                    switch priorityChoice {
                    case .standard(let priority):
                        todo.priority = priority
                        todo.customPriorityID = nil
                    case .custom(let id):
                        todo.customPriorityID = id
                    }
                    onSave(todo)
                } label: {
                    Text("Speichern")
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 8)
                        .background(Color.white, in: Capsule())
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.defaultAction)
                .disabled(todo.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(12)
        .transition(.move(edge: .top).combined(with: .opacity))
        .onAppear {
            hasDue = todo.due != nil
            date = todo.due ?? Date().addingTimeInterval(3600)
            priorityChoice = todo.customPriorityID.map(PriorityChoice.custom) ?? .standard(todo.priority)
        }
    }
}
