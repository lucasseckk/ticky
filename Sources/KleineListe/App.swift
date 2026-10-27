import SwiftUI
import AppKit

@main struct ToDoListApp: App {
    @NSApplicationDelegateAdaptor(NotificationAppDelegate.self) private var appDelegate
    @StateObject private var store = Store()
    init() { migratePreviousSettings() }
    var body: some Scene {
        MenuBarExtra {
            Panel(store: store)
        } label: {
            Image(systemName: store.count == 0 ? "checkmark.circle" : "checklist")
                .accessibilityLabel("To-Do List: \(store.count) offene To-Dos")
        }.menuBarExtraStyle(.window)
    }
}

private func migratePreviousSettings() {
    let defaults = UserDefaults.standard
    guard !defaults.bool(forKey: "didMigrateFromKleineListe") else { return }
    let oldValues = defaults.persistentDomain(forName: "de.lucasseck.kleineliste") ?? [:]
    for (key, value) in oldValues where defaults.object(forKey: key) == nil { defaults.set(value, forKey: key) }
    defaults.set(true, forKey: "didMigrateFromKleineListe")
}

struct Panel: View {
    @ObservedObject var store: Store
    @State private var panelVisible = false
    @State private var title = ""
    @State private var statusFilter = StatusFilter.open
    @State private var filter = TodoFilter()
    @State private var showSearch = false
    @FocusState private var searchFocused: Bool
    @State private var showSettings = false
    @State private var draft: Todo?
    @State private var draftIsNew = false
    @State private var hoveredGroupID: UUID?
    @State private var groupFrames: [UUID: CGRect] = [:]
    @State private var standardFrame = CGRect.zero
    @State private var hoveringStandard = false
    @State private var draggingTodoID: UUID?
    @State private var draggingGroupID: UUID?
    @State private var cardFrames: [UUID: CGRect] = [:]
    @State private var hoveredCardID: UUID?
    @State private var editingTodoID: UUID?
    @State private var showArchive = false
    @State private var confirmClearArchive = false
    @State private var editingTitle = ""
    @FocusState private var titleFieldFocused: Bool
    @AppStorage("dueView") private var dueView = false
    @AppStorage("manualSort") private var manualSort = false
    @State private var dragLocation = CGPoint.zero
    @AppStorage("backgroundColorV2") private var backgroundColorHex = "#FF0000"
    @AppStorage("highPriorityColor") private var highPriorityColorHex = "#C24033"
    @AppStorage("mediumPriorityColor") private var mediumPriorityColorHex = "#E0A63D"
    @AppStorage("lowPriorityColor") private var lowPriorityColorHex = "#94BD80"
    private var backgroundColor: Color { Color(hex: backgroundColorHex) }
    private var highPriorityColor: Color { Color(hex: highPriorityColorHex) }
    private var mediumPriorityColor: Color { Color(hex: mediumPriorityColorHex) }
    private var lowPriorityColor: Color { Color(hex: lowPriorityColorHex) }
    private var items: [Todo] {
        let manualOrder = Dictionary(uniqueKeysWithValues: store.todos.enumerated().map { ($1.id, $0) })
        return store.todos.filter { (showArchive ? $0.showsInArchive : !$0.archived) && filter.matches($0) && (showArchive || matchesStatus($0)) }.sorted {
            if $0.done != $1.done { return !$0.done }
            if manualSort { return manualOrder[$0.id, default: 0] < manualOrder[$1.id, default: 0] }
            if priorityLevel($0) != priorityLevel($1) { return priorityLevel($0) > priorityLevel($1) }
            if $0.due != $1.due { return ($0.due ?? .distantFuture) < ($1.due ?? .distantFuture) }
            return $0.created < $1.created
        }
    }
    private var filterActive: Bool { filter.isActive || statusFilter != .open }
    private func matchesStatus(_ todo: Todo) -> Bool {
        switch statusFilter {
        case .open: return shouldShow(todo)
        case .done: return todo.done
        case .all: return true
        }
    }
    private func shouldShow(_ todo: Todo) -> Bool {
        guard !todo.done else {
            guard let groupID = todo.groupID else { return false }
            return !groupIsComplete(groupID)
        }
        return true
    }
    private func groupIsComplete(_ groupID: UUID) -> Bool {
        let members = store.todos.filter { $0.groupID == groupID }
        guard !members.isEmpty else { return true }
        if members.contains(where: { $0.repeatRule != .none }) { return false }
        return members.allSatisfy(\.done)
    }
    private func priorityLevel(_ todo: Todo) -> Int {
        if let customID = todo.customPriorityID, let custom = store.customPriorities.first(where: { $0.id == customID }) { return custom.threatLevel + 2 }
        return todo.priority.rawValue
    }
    private func cardColor(for todo: Todo) -> Color {
        if let customID = todo.customPriorityID, let custom = store.customPriorities.first(where: { $0.id == customID }) { return Color(hex: custom.colorHex) }
        return todo.priority.cardColor(high: highPriorityColor, medium: mediumPriorityColor, low: lowPriorityColor)
    }
    private func borderColor(for todo: Todo) -> Color {
        if let customID = todo.customPriorityID, let custom = store.customPriorities.first(where: { $0.id == customID }) { return Color(hex: custom.colorHex).opacity(0.72) }
        return todo.priority.borderColor(high: highPriorityColor, medium: mediumPriorityColor, low: lowPriorityColor)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("To-Do List").font(.title2.bold())
                    Text(store.count == 0 ? "Alles erledigt." : "\(store.count) To-Dos offen").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button(action: toggleSearch) {
                    Image(systemName: "magnifyingglass").font(.title3)
                        .foregroundStyle(showSearch ? Color.accentColor : Color.primary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(showSearch ? "Suche schließen" : "Suche öffnen")
                .help(showSearch ? "Suche schließen" : "To-Dos suchen und filtern")
                Button { withAnimation(.easeOut(duration: 0.2)) { showArchive.toggle(); confirmClearArchive = false } } label: {
                    Image(systemName: showArchive ? "archivebox.fill" : "archivebox").font(.title3)
                        .foregroundStyle(showArchive ? Color.accentColor : Color.primary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(showArchive ? "Archiv schließen" : "Archiv öffnen")
                .help(showArchive ? "Zurück zur Liste" : "Archiv erledigter To-Dos")
                Button { withAnimation(.easeOut(duration: 0.2)) { dueView.toggle() } } label: {
                    Image(systemName: dueView ? "calendar.circle.fill" : "calendar").font(.title3)
                        .foregroundStyle(dueView ? Color.accentColor : Color.primary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(dueView ? "Nach Gruppen anzeigen" : "Nach Fälligkeit anzeigen")
                .help(dueView ? "Nach Gruppen anzeigen" : "Nach Fälligkeit anzeigen: Überfällig, Heute, Morgen …")
                Button { showSettings.toggle() } label: {
                    Image(systemName: "gearshape").font(.title3)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Einstellungen")
                .help("Einstellungen öffnen")
            }
            if showSettings {
                SettingsView(store: store, onClose: { showSettings = false })
            } else {
            if draft == nil {
                HStack {
                    Button(action: openNewEditor) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 10)
                                .fill(.quaternary.opacity(0.5))
                            HStack {
                                Text(title.isEmpty ? "Was steht an?" : title)
                                    .foregroundStyle(title.isEmpty ? .secondary : .primary)
                                Spacer()
                                Image(systemName: "plus.circle.fill")
                                    .font(.title2)
                                    .foregroundStyle(Color.accentColor)
                            }
                            .padding(12)
                        }
                        .frame(maxWidth: .infinity, minHeight: 52, maxHeight: 52)
                    }
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity)
                    .contentShape(RoundedRectangle(cornerRadius: 10))
                    .accessibilityLabel("Neues To-Do anlegen")
                }
                .padding(.horizontal, 12)
            }
            if let error = store.error { Text(error).font(.caption).foregroundStyle(.red).textSelection(.enabled) }
            if let todo = draft {
                Editor(todo: todo, isNew: draftIsNew, groups: store.groups, customPriorities: store.customPriorities, onSave: saveDraft, onCancel: { withAnimation(.easeOut(duration: 0.2)) { draft = nil } }).id(todo.id)
            } else {
                if showSearch { filterBar }
                ScrollView {
                    LazyVStack(spacing: 4) {
                        if showArchive { archiveHeader }
                        if items.isEmpty {
                            VStack(spacing: 10) {
                                Image(systemName: filterActive ? "magnifyingglass" : showArchive ? "archivebox" : "checkmark.seal").font(.system(size: 34))
                                Text(filterActive ? "Keine passenden To-Dos." : showArchive ? "Das Archiv ist leer." : "Platz für deinen nächsten Plan.")
                            }.foregroundStyle(.secondary).frame(maxWidth: .infinity).padding(.vertical, 40)
                        }
                        if showArchive {
                            ForEach(items) { item in todoCard(item) }
                        } else if dueView {
                            ForEach(DueBucket.allCases) { bucket in dueSection(bucket) }
                        } else {
                        VStack(spacing: 4) {
                            ForEach(standardItems) { item in todoCard(item) }
                            if standardItems.isEmpty && draggingTodoID != nil {
                                Text("To-Dos hierher ziehen, um sie aus einer Gruppe zu lösen.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity, minHeight: 68)
                            }
                        }
                        .contentShape(Rectangle())
                        .background(Color.accentColor.opacity(hoveringStandard ? 0.15 : 0), in: RoundedRectangle(cornerRadius: 14))
                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.accentColor.opacity(hoveringStandard ? 0.6 : 0), lineWidth: 2))
                        .background(GeometryReader { proxy in
                            Color.clear.preference(key: StandardFramePreferenceKey.self, value: proxy.frame(in: .named("todo-list")))
                        })
                        ForEach(visibleGroups) { group in groupBlock(group) }
                        }
                    }
                }
                .coordinateSpace(name: "todo-list")
                .frame(minHeight: 160, maxHeight: .infinity)
                .onPreferenceChange(GroupFramePreferenceKey.self) { groupFrames = $0 }
                .onPreferenceChange(CardFramePreferenceKey.self) { cardFrames = $0 }
                .onPreferenceChange(StandardFramePreferenceKey.self) { standardFrame = $0 }
                .safeAreaInset(edge: .bottom) {
                    if !showArchive, store.archivableCount > 0 {
                        Button { withAnimation { store.archiveDone() } } label: {
                            Label("\(store.archivableCount) erledigte archivieren", systemImage: "archivebox")
                                .font(.caption)
                        }
                        .buttonStyle(.bordered)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 6)
                        .help("Erledigte, nicht wiederkehrende To-Dos ins Archiv verschieben")
                    }
                }
                .overlay(alignment: .topLeading) {
                    if let draggingTodoID,
                       let draggedTodo = store.todos.first(where: { $0.id == draggingTodoID }) {
                        todoDragPreview(draggedTodo)
                            .position(x: dragLocation.x + 130, y: dragLocation.y + 34)
                            .allowsHitTesting(false)
                    }
                }
            }
            }
        }
        .overlay(alignment: .bottom) {
            if let step = store.undoStep { undoBar(step) }
        }
        .animation(.easeOut(duration: 0.2), value: store.undoStep?.id)
        .padding(20)
        // Fixed list height: the menu bar window does not reliably grow, so the search bar takes space from the list instead.
        .frame(width: 460, height: showSettings || draft != nil ? nil : 560, alignment: .top)
        .background(backgroundColor.opacity(0.18), in: RoundedRectangle(cornerRadius: 16))
        .opacity(panelVisible ? 1 : 0)
        .scaleEffect(panelVisible ? 1 : 0.96)
        .onAppear {
            withAnimation(.easeOut(duration: 0.2)) { panelVisible = true }
            rescheduleNotifications()
        }
    }
    private func undoBar(_ step: UndoStep) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "arrow.uturn.backward.circle.fill").foregroundStyle(Color.accentColor)
            Text(step.label).lineLimit(1)
            Spacer(minLength: 8)
            Button("Rückgängig") {
                withAnimation { store.undo() }
                rescheduleNotifications()
            }
            .keyboardShortcut("z", modifiers: .command)
            .help("Rückgängig (⌘Z)")
            Button { store.dismissUndo(step.id) } label: { Image(systemName: "xmark") }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .accessibilityLabel("Hinweis schließen")
        }
        .font(.callout)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.regularMaterial, in: Capsule())
        .shadow(color: .black.opacity(0.2), radius: 8, y: 3)
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .task(id: step.id) {
            try? await Task.sleep(for: .seconds(8))
            store.dismissUndo(step.id)
        }
    }
    private func openNewEditor() {
        draftIsNew = true
        withAnimation(.easeOut(duration: 0.2)) { draft = Todo(title: title) }
    }
    private func toggleSearch() {
        withAnimation(.easeOut(duration: 0.2)) {
            showSearch.toggle()
            // Closed search must not leave invisible filters behind.
            if !showSearch { resetFilter() }
        }
        searchFocused = showSearch
    }
    private var filterBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                TextField("To-Dos suchen", text: $filter.query)
                    .textFieldStyle(.roundedBorder)
                    .focused($searchFocused)
                    .onExitCommand(perform: toggleSearch)
                Menu {
                    Picker("Status", selection: $statusFilter) {
                        ForEach(StatusFilter.allCases) { Text($0.label).tag($0) }
                    }
                    Picker("Gruppe", selection: $filter.group) {
                        Text("Alle").tag(GroupFilter.all)
                        Text("Ohne Gruppe").tag(GroupFilter.ungrouped)
                        ForEach(store.groups) { Text($0.name).tag(GroupFilter.group($0.id)) }
                    }
                    Picker("Priorität", selection: $filter.priority) {
                        Text("Alle").tag(Optional<PriorityChoice>.none)
                        ForEach(Priority.allCases.reversed()) { Text($0.label).tag(Optional(PriorityChoice.standard($0))) }
                        ForEach(store.customPriorities) { Text($0.name).tag(Optional(PriorityChoice.custom($0.id))) }
                    }
                    Picker("Fälligkeit", selection: $filter.due) {
                        ForEach(DueFilter.allCases) { Text($0.label).tag($0) }
                    }
                    Divider()
                    Picker("Sortierung", selection: $manualSort) {
                        Text("Automatisch").tag(false)
                        Text("Manuell").tag(true)
                    }
                    Button("Filter zurücksetzen", action: resetFilter).disabled(!filterActive)
                } label: {
                    Image(systemName: filterActive ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .accessibilityLabel("Filter")
                .help("To-Dos filtern")
                if filterActive {
                    Button(action: resetFilter) { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("Suche und Filter zurücksetzen")
                        .help("Suche und Filter zurücksetzen")
                }
            }
            presetRow("Schnell") {
                presetChip("Überfällig", "exclamationmark.circle", filter.due == .overdue) { filter.due = filter.due == .overdue ? .all : .overdue }
                presetChip("Heute", "calendar", filter.due == .today) { filter.due = filter.due == .today ? .all : .today }
                presetChip("Ohne Datum", "calendar.badge.minus", filter.due == DueFilter.none) { filter.due = filter.due == DueFilter.none ? .all : DueFilter.none }
                presetChip("Erledigt", "checkmark.circle", statusFilter == .done) { statusFilter = statusFilter == .done ? .open : .done }
            }
            presetRow("Priorität") {
                ForEach(Priority.allCases.reversed()) { priority in
                    priorityChip(priority.label, .standard(priority))
                }
            }
            presetRow("Eigene") {
                ForEach(store.customPriorities) { priority in
                    priorityChip(priority.name, .custom(priority.id))
                }
                if store.customPriorities.isEmpty {
                    presetChip("Eigene Priorität anlegen", "plus", false) { showSettings = true }
                }
            }
            presetRow("Gruppe") {
                presetChip("Ohne Gruppe", "tray", filter.group == .ungrouped) { filter.group = filter.group == .ungrouped ? .all : .ungrouped }
                ForEach(store.groups) { group in
                    presetChip(group.name, "folder", filter.group == .group(group.id)) {
                        filter.group = filter.group == .group(group.id) ? .all : .group(group.id)
                    }
                }
            }
        }
        .padding(.horizontal, 12)
        .transition(.move(edge: .top).combined(with: .opacity))
    }
    private func presetRow<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 8) {
            Text(label).font(.caption.bold()).foregroundStyle(.secondary).frame(width: 56, alignment: .leading)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) { content() }
            }
        }
    }
    private func priorityChip(_ label: String, _ choice: PriorityChoice) -> some View {
        presetChip(label, "flag", filter.priority == choice) { filter.priority = filter.priority == choice ? nil : choice }
    }
    private func presetChip(_ label: String, _ systemImage: String, _ isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(label, systemImage: systemImage)
                .font(.caption)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(isOn ? Color.accentColor : Color.secondary.opacity(0.15), in: Capsule())
                .foregroundStyle(isOn ? Color.white : Color.primary)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
    private func resetFilter() {
        filter = TodoFilter()
        statusFilter = .open
    }
    private var visibleGroups: [TodoGroup] {
        guard filterActive && draggingTodoID == nil else { return store.groups }
        return store.groups.filter { !groupedItems(for: $0.id).isEmpty }
    }
    private var archiveHeader: some View {
        HStack {
            Text("Archiv").font(.headline)
            Text("\(items.count)").font(.caption).foregroundStyle(.secondary)
            Spacer()
            if store.todos.contains(where: \.showsInArchive) {
                Button(confirmClearArchive ? "Wirklich alle löschen?" : "Archiv leeren") {
                    if confirmClearArchive {
                        withAnimation { store.clearArchive() }
                        confirmClearArchive = false
                    } else {
                        confirmClearArchive = true
                    }
                }
                .foregroundStyle(confirmClearArchive ? Color.red : Color.primary)
            }
        }
        .padding(.horizontal, 4)
        .padding(.bottom, 4)
    }
    @ViewBuilder private func dueSection(_ bucket: DueBucket) -> some View {
        let now = Date()
        let bucketItems = items.filter { DueBucket($0, now: now) == bucket }
            .sorted { ($0.due ?? .distantFuture) < ($1.due ?? .distantFuture) }
        if !bucketItems.isEmpty {
            HStack {
                Text(bucket.label).font(.headline).foregroundStyle(bucket == .overdue ? Color.red : Color.primary)
                Text("\(bucketItems.count)").font(.caption).foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.top, 8)
            .padding(.horizontal, 4)
            ForEach(bucketItems) { item in todoCard(item) }
        }
    }
    private var standardItems: [Todo] { items.filter { $0.groupID == nil } }
    private func groupedItems(for groupID: UUID) -> [Todo] { items.filter { $0.groupID == groupID } }
    @ViewBuilder private func groupBlock(_ group: TodoGroup) -> some View {
        let groupItems = groupedItems(for: group.id)
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(group.name).font(.title3.bold())
                Spacer()
                Image(systemName: "line.3.horizontal").foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
            .help("Ziehen, um die Gruppe zu verschieben")
            .gesture(DragGesture(minimumDistance: 8, coordinateSpace: .named("todo-list"))
                .onChanged { value in
                    draggingGroupID = group.id
                    hoveredGroupID = groupFrames.first(where: { $0.key != group.id && $0.value.contains(value.location) })?.key
                }
                .onEnded { _ in
                    if let target = hoveredGroupID { withAnimation { store.reorderGroup(group.id, to: target) } }
                    draggingGroupID = nil
                    hoveredGroupID = nil
                })
            Text("Notizen").font(.caption.bold()).foregroundStyle(.secondary)
            TextEditor(text: groupNotesBinding(for: group))
                .frame(minHeight: 58, maxHeight: 84)
                .padding(4)
                .background(.background.opacity(0.7), in: RoundedRectangle(cornerRadius: 8))
            ForEach(groupItems) { item in todoCard(item) }
            if groupItems.isEmpty {
                Text("Noch keine To-Dos in dieser Gruppe.").font(.caption).foregroundStyle(.secondary).padding(.vertical, 6)
            }
        }
        .padding(14)
        .background(Color(hex: group.colorHex).opacity(hoveredGroupID == group.id ? 0.22 : 0.10), in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color(hex: group.colorHex).opacity(0.55), lineWidth: 2))
        .opacity(draggingGroupID == group.id ? 0.4 : 1)
        .background(GeometryReader { proxy in
            Color.clear.preference(key: GroupFramePreferenceKey.self, value: [group.id: proxy.frame(in: .named("todo-list"))])
        })
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
    private func groupNotesBinding(for group: TodoGroup) -> Binding<String> {
        Binding(
            get: { store.groups.first(where: { $0.id == group.id })?.notes ?? "" },
            set: { notes in
                var updated = group
                updated.notes = notes
                store.updateGroup(updated)
            }
        )
    }
    @ViewBuilder private func todoCard(_ item: Todo) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Button { withAnimation { store.toggle(item) }; rescheduleNotifications() } label: {
                Image(systemName: item.done ? "checkmark.circle.fill" : "circle").font(.title3)
                    .foregroundStyle(item.done ? Color.green : Color.secondary)
            }.buttonStyle(.plain).accessibilityLabel(item.done ? "Wieder öffnen: \(item.title)" : "Erledigen: \(item.title)")
            VStack(alignment: .leading, spacing: 5) {
                if editingTodoID == item.id {
                    TextField("Titel", text: $editingTitle)
                        .textFieldStyle(.plain)
                        .focused($titleFieldFocused)
                        .onSubmit { commitTitle(item.id) }
                        .onExitCommand { editingTodoID = nil }
                        .onChange(of: titleFieldFocused) { _, focused in
                            if !focused { commitTitle(item.id) }
                        }
                } else {
                    Text(item.title).strikethrough(item.done).foregroundStyle(item.done ? .secondary : .primary)
                        .fixedSize(horizontal: false, vertical: true)
                        .onTapGesture(count: 2) { startEditingTitle(item) }
                        .help("Doppelklick zum Umbenennen")
                }
                if let due = item.due {
                    Text(due, format: .dateTime.day().month().hour().minute())
                        .font(.caption)
                        .foregroundStyle(!item.done && due < Date() ? Color.red : Color.secondary)
                }
                if dueView, let group = store.groups.first(where: { $0.id == item.groupID }) {
                    Label(group.name, systemImage: "folder")
                        .font(.caption2)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(Color(hex: group.colorHex).opacity(0.35), in: Capsule())
                }
            }
            Spacer(minLength: 0)
            Menu {
                Button("Umbenennen") { startEditingTitle(item) }
                Picker("Priorität", selection: priorityBinding(for: item)) {
                    ForEach(Priority.allCases.reversed()) { Text($0.label).tag(PriorityChoice.standard($0)) }
                    if !store.customPriorities.isEmpty {
                        Divider()
                        ForEach(store.customPriorities) { Text($0.name).tag(PriorityChoice.custom($0.id)) }
                    }
                }
                Picker("Gruppe", selection: groupBinding(for: item)) {
                    Text("Keine Gruppe").tag(Optional<UUID>.none)
                    ForEach(store.groups) { Text($0.name).tag(Optional($0.id)) }
                }
                Button("Fälligkeit und Wiederholung …") { draftIsNew = false; draft = item }
                if item.archived {
                    Button("Wiederherstellen") { withAnimation { store.setArchived(item.id, false) } }
                } else if item.canArchive {
                    Button("Archivieren") { withAnimation { store.setArchived(item.id, true) } }
                }
                Divider()
                Button("Löschen", role: .destructive) { withAnimation { store.delete(item) }; rescheduleNotifications() }
            } label: { Image(systemName: "ellipsis") }
            .menuStyle(.borderlessButton).fixedSize().accessibilityLabel("Optionen für \(item.title)")
        }
        .padding(14)
        .frame(minHeight: 68)
        .background(cardColor(for: item), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(borderColor(for: item), lineWidth: 1.5))
        .overlay(alignment: .top) {
            if hoveredCardID == item.id {
                Capsule().fill(Color.accentColor).frame(height: 4).offset(y: -4)
            }
        }
        .opacity(draggingTodoID == item.id ? 0.28 : (item.done ? 0.6 : 1))
        .contentShape(RoundedRectangle(cornerRadius: 12))
        .background(GeometryReader { proxy in
            Color.clear.preference(key: CardFramePreferenceKey.self, value: [item.id: proxy.frame(in: .named("todo-list"))])
        })
        // Only this gesture handles dragging: a parallel system .onDrag cancels it without calling onEnded.
        .simultaneousGesture(DragGesture(minimumDistance: 4, coordinateSpace: .named("todo-list"))
            .onChanged { value in
                // Time sections are derived from due dates, so there is nothing to drop onto there.
                guard !dueView, !showArchive, abs(value.translation.width) > 8 || abs(value.translation.height) > 8 else { return }
                draggingTodoID = item.id
                dragLocation = value.location
                hoveredCardID = manualSort ? cardFrames.first(where: { $0.key != item.id && $0.value.contains(value.location) })?.key : nil
                hoveredGroupID = groupFrames.first(where: { $0.value.contains(value.location) })?.key
                hoveringStandard = hoveredGroupID == nil && standardFrame.contains(value.location)
            }
            .onEnded { value in
                guard draggingTodoID == item.id else { return }
                let groupID = groupFrames.first(where: { $0.value.contains(value.location) })?.key
                let isStandardDrop = groupID == nil && standardFrame.contains(value.location)
                if let target = hoveredCardID {
                    withAnimation { store.reorderTodo(item.id, to: target) }
                } else if (groupID != nil || isStandardDrop), groupID != item.groupID {
                    withAnimation { store.moveTodo(item.id, to: groupID) }
                    rescheduleNotifications()
                }
                draggingTodoID = nil
                hoveredCardID = nil
                hoveredGroupID = nil
                hoveringStandard = false
            })
        .transition(.asymmetric(insertion: .scale(scale: 0.55, anchor: .top).combined(with: .move(edge: .top)).combined(with: .opacity), removal: .opacity))
    }
    private func startEditingTitle(_ item: Todo) {
        editingTitle = item.title
        editingTodoID = item.id
        titleFieldFocused = true
    }
    private func commitTitle(_ id: UUID) {
        guard editingTodoID == id else { return }
        editingTodoID = nil
        guard var todo = store.todos.first(where: { $0.id == id }), todo.title != editingTitle else { return }
        todo.title = editingTitle
        store.save(todo)
        rescheduleNotifications()
    }
    private func priorityBinding(for item: Todo) -> Binding<PriorityChoice> {
        Binding(
            get: { item.customPriorityID.map(PriorityChoice.custom) ?? .standard(item.priority) },
            set: { choice in
                guard var todo = store.todos.first(where: { $0.id == item.id }) else { return }
                switch choice {
                case .standard(let priority):
                    todo.priority = priority
                    todo.customPriorityID = nil
                case .custom(let id):
                    todo.customPriorityID = id
                }
                withAnimation { store.save(todo) }
                rescheduleNotifications()
            }
        )
    }
    private func groupBinding(for item: Todo) -> Binding<UUID?> {
        Binding(
            get: { item.groupID },
            set: { groupID in
                withAnimation { store.moveTodo(item.id, to: groupID) }
                rescheduleNotifications()
            }
        )
    }
    @ViewBuilder private func todoDragPreview(_ item: Todo) -> some View {
        HStack(spacing: 8) {
            Image(systemName: item.done ? "checkmark.circle.fill" : "circle")
            Text(item.title).lineLimit(1)
        }
        .font(.body)
        .foregroundStyle(.primary)
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .frame(width: 260, alignment: .leading)
        .background(cardColor(for: item).opacity(0.55), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(borderColor(for: item), lineWidth: 1.5))
        .opacity(0.62)
        .shadow(color: .black.opacity(0.18), radius: 8, y: 4)
    }
    private func add() {
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        saveDraft(Todo(title: title))
    }
    private func saveDraft(_ todo: Todo) {
        withAnimation(.spring(response: 0.5, dampingFraction: 0.62)) {
            store.save(todo)
            title = ""
            draft = nil
        }
        rescheduleNotifications()
    }
    private func rescheduleNotifications() {
        NotificationManager.shared.reschedule(todos: store.todos, customPriorities: store.customPriorities)
    }
}

private struct GroupFramePreferenceKey: PreferenceKey {
    static let defaultValue: [UUID: CGRect] = [:]
    static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}

private struct CardFramePreferenceKey: PreferenceKey {
    static let defaultValue: [UUID: CGRect] = [:]
    static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}

private struct StandardFramePreferenceKey: PreferenceKey {
    static let defaultValue = CGRect.zero
    // Sibling views without this preference report .zero; they must not overwrite the real frame.
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        let next = nextValue()
        if next != .zero { value = next }
    }
}

struct SettingsView: View {
    @ObservedObject var store: Store
    let onClose: () -> Void
    @State private var selectedTab = 0
    @AppStorage("manualSort") private var manualSort = false
    @AppStorage("backgroundColorV2") private var backgroundColorHex = "#FF0000"
    @AppStorage("highPriorityColor") private var highPriorityColorHex = "#C24033"
    @AppStorage("mediumPriorityColor") private var mediumPriorityColorHex = "#E0A63D"
    @AppStorage("lowPriorityColor") private var lowPriorityColorHex = "#94BD80"
    @AppStorage("defaultBackgroundColor") private var defaultBackgroundHex = "#FF0000"
    @AppStorage("defaultHighPriorityColor") private var defaultHighHex = "#C24033"
    @AppStorage("defaultMediumPriorityColor") private var defaultMediumHex = "#E0A63D"
    @AppStorage("defaultLowPriorityColor") private var defaultLowHex = "#94BD80"
    @AppStorage("notificationsEnabled") private var notificationsEnabled = false
    @AppStorage("notificationSound") private var notificationSound = true
    @AppStorage("animatedNotificationPopup") private var animatedNotificationPopup = true
    @AppStorage("highPriorityLeadMinutes") private var highPriorityLeadMinutes = 30
    @AppStorage("mediumPriorityLeadMinutes") private var mediumPriorityLeadMinutes = 120
    @AppStorage("lowPriorityReminderHour") private var lowPriorityReminderHour = 9
    @State private var notificationPermission: NotificationPermission?
    @State private var testResult: (text: String, success: Bool)?
    @State private var dataResult: (text: String, success: Bool)?

    private var backgroundIsDark: Bool {
        let cleaned = backgroundColorHex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var value: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&value)
        let red = Double((value >> 16) & 0xFF) / 255
        let green = Double((value >> 8) & 0xFF) / 255
        let blue = Double(value & 0xFF) / 255
        let brightness = 0.2126 * red + 0.7152 * green + 0.0722 * blue
        return brightness < 0.5
    }
    private var settingsSurface: Color { backgroundIsDark ? .white : .black }
    private var settingsText: Color { backgroundIsDark ? .black : .white }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                Button(action: onClose) {
                    Image(systemName: "arrow.left")
                }
                .buttonStyle(.plain)
                .font(.title2)
                .frame(width: 36, height: 36)
                .accessibilityLabel("Zurück zur To-Do-Liste")
                Text("Einstellungen").font(.headline)
            }
            Picker("Bereich", selection: $selectedTab) {
                Text("Allgemein").tag(0)
                Text("Darstellung").tag(1)
                Text("Benachrichtigungen").tag(2)
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            Group {
                if selectedTab == 0 {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) {
                            SettingsCard(title: "Sortierung", systemImage: "arrow.up.arrow.down", subtitle: manualSort
                                ? "Ziehe To-Dos auf andere To-Dos und Gruppen am Griff ≡, um die Reihenfolge festzulegen."
                                : "Offene zuerst, dann nach Priorität, Fälligkeit und Erstellung. Gruppen lassen sich immer am Griff ≡ verschieben.") {
                                Picker("Sortierung", selection: $manualSort) {
                                    Text("Automatisch").tag(false)
                                    Text("Manuell").tag(true)
                                }
                                .pickerStyle(.segmented)
                                .labelsHidden()
                            }
                            SettingsCard(title: "Gruppen", systemImage: "folder", subtitle: "Gruppen bündeln To-Dos mit gemeinsamen Notizen.") {
                                ForEach(store.groups) { group in
                                    SettingsItemRow(name: group.name, colorHex: group.colorHex, detail: nil) { store.deleteGroup(group) }
                                }
                                if store.groups.isEmpty {
                                    Text("Noch keine Gruppen.").font(.caption).foregroundStyle(.secondary)
                                }
                                HStack {
                                    TextField("Name der neuen Gruppe", text: $newGroupName)
                                        .textFieldStyle(.roundedBorder)
                                        .onSubmit(createGroup)
                                    Button(action: createGroup) { Label("Anlegen", systemImage: "plus") }
                                        .buttonStyle(.borderedProminent)
                                        .disabled(newGroupName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                                }
                            }
                            SettingsCard(title: "Eigene Prioritäten", systemImage: "flag", subtitle: "Stufe 1 (niedrig) bis 5 (kritisch) bestimmt Sortierung und Erinnerungen.") {
                                ForEach(store.customPriorities) { priority in
                                    SettingsItemRow(name: priority.name, colorHex: priority.colorHex, detail: "Stufe \(priority.threatLevel)") { store.deleteCustomPriority(priority) }
                                }
                                if store.customPriorities.isEmpty {
                                    Text("Noch keine eigenen Prioritäten.").font(.caption).foregroundStyle(.secondary)
                                }
                                HStack {
                                    TextField("Name der neuen Priorität", text: $newPriorityName)
                                        .textFieldStyle(.roundedBorder)
                                        .onSubmit(createPriority)
                                    Picker("Stufe", selection: $newPriorityThreatLevel) {
                                        ForEach(1...5, id: \.self) { Text("Stufe \($0)").tag($0) }
                                    }
                                    .labelsHidden()
                                    .fixedSize()
                                    Button(action: createPriority) { Label("Anlegen", systemImage: "plus") }
                                        .buttonStyle(.borderedProminent)
                                        .disabled(newPriorityName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                                }
                            }
                            SettingsCard(title: "Daten sichern", systemImage: "externaldrive", subtitle: "Enthält alle To-Dos, Gruppen mit Notizen und Prioritäten im Klartext – sicher aufbewahren. Vor jedem Import wird der aktuelle Stand automatisch gesichert.") {
                                HStack {
                                    Button(action: exportBackup) { Label("Exportieren …", systemImage: "square.and.arrow.up") }
                                    Button(action: importBackup) { Label("Importieren …", systemImage: "square.and.arrow.down") }
                                }
                                if let dataResult {
                                    Label(dataResult.text, systemImage: dataResult.success ? "checkmark.circle.fill" : "xmark.octagon.fill")
                                        .font(.caption)
                                        .foregroundStyle(dataResult.success ? Color.green : Color.red)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                        .padding(12)
                    }
                } else if selectedTab == 1 {
                    ScrollView(.vertical) {
                        VStack(alignment: .leading, spacing: 12) {
                            SettingsCard(title: "Hintergrund", systemImage: "paintpalette", subtitle: nil) {
                                ColorSettingRow(label: "Farbe", hex: $backgroundColorHex)
                            }
                            SettingsCard(title: "Prioritätsfarben", systemImage: "flag", subtitle: nil) {
                                ColorSettingRow(label: "Hoch", hex: $highPriorityColorHex)
                                ColorSettingRow(label: "Mittel", hex: $mediumPriorityColorHex)
                                ColorSettingRow(label: "Niedrig", hex: $lowPriorityColorHex)
                                ForEach(store.customPriorities) { priority in
                                    ColorSettingRow(label: priority.name, hex: customPriorityColorBinding(for: priority.id))
                                }
                            }
                            SettingsCard(title: "Gruppenfarben", systemImage: "folder", subtitle: store.groups.isEmpty ? "Lege zuerst unter Allgemein eine Gruppe an." : nil) {
                                ForEach(store.groups) { group in
                                    ColorSettingRow(label: group.name, hex: groupColorBinding(for: group.id))
                                }
                            }
                            SettingsCard(title: "Standardfarben", systemImage: "arrow.counterclockwise", subtitle: "Diese Farben werden beim Zurücksetzen verwendet.") {
                                ColorSettingRow(label: "Hintergrund", hex: $defaultBackgroundHex)
                                ColorSettingRow(label: "Hoch", hex: $defaultHighHex)
                                ColorSettingRow(label: "Mittel", hex: $defaultMediumHex)
                                ColorSettingRow(label: "Niedrig", hex: $defaultLowHex)
                                Button("Auf Standard zurücksetzen") {
                                    backgroundColorHex = defaultBackgroundHex
                                    highPriorityColorHex = defaultHighHex
                                    mediumPriorityColorHex = defaultMediumHex
                                    lowPriorityColorHex = defaultLowHex
                                }
                            }
                        }
                        .padding(12)
                    }
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) {
                            SettingsCard(title: "Benachrichtigungen", systemImage: "bell", subtitle: nil) {
                                Label(notificationStatus.text, systemImage: notificationStatus.icon)
                                    .font(.callout.weight(.medium))
                                    .foregroundStyle(notificationStatus.color)
                                if notificationPermission == .denied {
                                    Button("Mitteilungen in Systemeinstellungen öffnen") {
                                        guard let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings") else { return }
                                        NSWorkspace.shared.open(url)
                                    }
                                }
                                Toggle("System-Push und Banner", isOn: $notificationsEnabled)
                                    .onChange(of: notificationsEnabled) { _, enabled in
                                        if enabled {
                                            NotificationManager.shared.requestAuthorization { _ in
                                                DispatchQueue.main.async { refreshNotificationPermission() }
                                            }
                                        } else {
                                            rescheduleNotifications()
                                        }
                                    }
                                Toggle("Ton abspielen", isOn: $notificationSound)
                                Toggle("Animiertes Pop-up beim Klick auf eine Mitteilung", isOn: $animatedNotificationPopup)
                                HStack {
                                    Button("Testbenachrichtigung senden") {
                                        testResult = ("Wird gesendet …", true)
                                        NotificationManager.shared.sendTestNotification { error in
                                            DispatchQueue.main.async {
                                                testResult = error.map { ($0, false) } ?? ("Gesendet – erscheint in etwa 1 Sekunde.", true)
                                                refreshNotificationPermission()
                                            }
                                        }
                                    }
                                    if let testResult {
                                        Label(testResult.text, systemImage: testResult.success ? "checkmark.circle.fill" : "xmark.octagon.fill")
                                            .font(.caption)
                                            .foregroundStyle(testResult.success ? Color.green : Color.red)
                                    }
                                }
                            }
                            SettingsCard(title: "Automatische Erinnerungen", systemImage: "clock", subtitle: "Eigene Prioritäten: Stufe 4–5 folgt Hoch, 2–3 Mittel und 1 Niedrig.") {
                                Picker("Hohe Priorität", selection: $highPriorityLeadMinutes) {
                                    reminderLeadOptions
                                }
                                Picker("Mittlere Priorität", selection: $mediumPriorityLeadMinutes) {
                                    reminderLeadOptions
                                }
                                Picker("Niedrige Priorität täglich", selection: $lowPriorityReminderHour) {
                                    ForEach(6...22, id: \.self) { hour in Text(String(format: "%02d:00", hour)).tag(hour) }
                                }
                            }
                        }
                        .padding(12)
                        .onChange(of: notificationSound) { _, _ in rescheduleNotifications() }
                        .onChange(of: highPriorityLeadMinutes) { _, _ in rescheduleNotifications() }
                        .onChange(of: mediumPriorityLeadMinutes) { _, _ in rescheduleNotifications() }
                        .onChange(of: lowPriorityReminderHour) { _, _ in rescheduleNotifications() }
                        .onAppear { refreshNotificationPermission() }
                    }
                }
            }
            .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .move(edge: .leading).combined(with: .opacity)))
            .foregroundStyle(settingsText)
            // System controls must match the contrasting surface, not the system appearance.
            .environment(\.colorScheme, backgroundIsDark ? .light : .dark)
            .frame(maxWidth: .infinity, minHeight: 400, maxHeight: 400, alignment: .topLeading)
            .background(settingsSurface, in: RoundedRectangle(cornerRadius: 10))
        }
    }

    @State private var newGroupName = ""
    @State private var newPriorityName = ""
    @State private var newPriorityThreatLevel = 3

    private func exportBackup() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "To-Do-List-Sicherung \(Date().formatted(.iso8601.year().month().day())).json"
        panel.allowedContentTypes = [.json]
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try store.exportData().write(to: url, options: .atomic)
            dataResult = ("Exportiert: \(url.lastPathComponent)", true)
        } catch {
            dataResult = ("Export fehlgeschlagen: \(error.localizedDescription)", false)
        }
    }

    private func importBackup() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let safety = try store.importData(Data(contentsOf: url))
            rescheduleNotifications()
            dataResult = ("Importiert. Vorheriger Stand gesichert in Backups/\(safety.lastPathComponent)", true)
        } catch {
            dataResult = ("Nichts geändert – \(error.localizedDescription)", false)
        }
    }

    private func createGroup() {
        store.createGroup(name: newGroupName)
        newGroupName = ""
    }

    private func createPriority() {
        store.createCustomPriority(name: newPriorityName, threatLevel: newPriorityThreatLevel)
        newPriorityName = ""
    }

    private func customPriorityColorBinding(for id: UUID) -> Binding<String> {
        Binding(
            get: { store.customPriorities.first(where: { $0.id == id })?.colorHex ?? "#94BD80" },
            set: { newColor in
                guard var priority = store.customPriorities.first(where: { $0.id == id }) else { return }
                priority.colorHex = newColor
                store.updateCustomPriority(priority)
            }
        )
    }

    private func groupColorBinding(for id: UUID) -> Binding<String> {
        Binding(
            get: { store.groups.first(where: { $0.id == id })?.colorHex ?? "#6C5CE7" },
            set: { newColor in
                guard var group = store.groups.first(where: { $0.id == id }) else { return }
                group.colorHex = newColor
                store.updateGroup(group)
            }
        )
    }

    @ViewBuilder private var reminderLeadOptions: some View {
        Text("5 Minuten vorher").tag(5)
        Text("15 Minuten vorher").tag(15)
        Text("30 Minuten vorher").tag(30)
        Text("1 Stunde vorher").tag(60)
        Text("2 Stunden vorher").tag(120)
        Text("1 Tag vorher").tag(1440)
    }

    private func rescheduleNotifications() {
        NotificationManager.shared.reschedule(todos: store.todos, customPriorities: store.customPriorities)
    }

    private func refreshNotificationPermission() {
        NotificationManager.shared.permission { permission in
            DispatchQueue.main.async {
                notificationPermission = permission
                if permission == .denied { notificationsEnabled = false }
                rescheduleNotifications()
            }
        }
    }

    private var notificationStatus: (text: String, icon: String, color: Color) {
        switch notificationPermission {
        case nil: return ("Status wird geprüft …", "hourglass", .secondary)
        case .denied: return ("Von macOS blockiert", "bell.slash.fill", .red)
        case .notDetermined: return ("Noch nicht erlaubt – wird beim Einschalten abgefragt", "bell.badge", .orange)
        case .allowed: return notificationsEnabled
            ? ("Aktiv – Erinnerungen werden geplant", "bell.fill", .green)
            : ("Erlaubt, aber ausgeschaltet", "bell", .secondary)
        }
    }

}

struct SettingsCard<Content: View>: View {
    let title: String
    let systemImage: String
    let subtitle: String?
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: systemImage).font(.headline)
            if let subtitle {
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
            content
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.foreground.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.foreground.opacity(0.18)))
    }
}

struct SettingsItemRow: View {
    let name: String
    let colorHex: String
    let detail: String?
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Circle().fill(Color(hex: colorHex)).frame(width: 12, height: 12)
            Text(name)
            Spacer()
            if let detail {
                Text(detail)
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(.foreground.opacity(0.1), in: Capsule())
            }
            Button(action: onDelete) { Image(systemName: "trash") }
                .buttonStyle(.plain)
                .foregroundStyle(.red)
                .accessibilityLabel("\(name) löschen")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(.foreground.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
    }
}

struct ColorSettingRow: View {
    let label: String
    @Binding var hex: String
    @State private var showingPicker = false

    var body: some View {
        HStack {
            Text(label)
            Spacer()
            Button {
                showingPicker = true
            } label: {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(hex: hex))
                    .frame(width: 58, height: 28)
                    .overlay {
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.primary.opacity(0.35), lineWidth: 1)
                    }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Farbe für \(label) ändern")
            .popover(isPresented: $showingPicker, arrowEdge: .trailing) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Farbe auswählen").font(.headline)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 30))], spacing: 8) {
                        ForEach(Self.palette, id: \.self) { colorHex in
                            Button {
                                hex = colorHex
                                showingPicker = false
                            } label: {
                                Circle()
                                    .fill(Color(hex: colorHex))
                                    .frame(width: 30, height: 30)
                                    .overlay {
                                        Circle().stroke(Color.primary.opacity(hex == colorHex ? 0.9 : 0.25), lineWidth: hex == colorHex ? 3 : 1)
                                    }
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Farbe \(colorHex)")
                        }
                    }
                }
                .padding(16)
                .foregroundStyle(.white)
                .background(Color(white: 0.22), in: RoundedRectangle(cornerRadius: 14))
            }
        }
    }

    private static let palette = [
        "#FFFFFF", "#F2F2F2", "#D9D9D9", "#808080", "#333333", "#000000",
        "#FF0000", "#C24033", "#FF7A59", "#FFB000", "#E0A63D", "#FFE066",
        "#94BD80", "#34A853", "#00A878", "#5BC0EB", "#2F80ED", "#6C5CE7",
        "#B36BCE", "#F29BB2", "#8B5E3C"
    ]
}

extension Color {
    init(hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var value: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&value)
        let red = Double((value >> 16) & 0xFF) / 255
        let green = Double((value >> 8) & 0xFF) / 255
        let blue = Double(value & 0xFF) / 255
        self.init(red: red, green: green, blue: blue)
    }

    var hexString: String {
        let color = NSColor(self).usingColorSpace(.sRGB) ?? .black
        let red = Int(round(color.redComponent * 255))
        let green = Int(round(color.greenComponent * 255))
        let blue = Int(round(color.blueComponent * 255))
        return String(format: "#%02X%02X%02X", red, green, blue)
    }
}

private extension Priority {
    func cardColor(high: Color, medium: Color, low: Color) -> Color {
        switch self {
        case .high: return high
        case .normal: return medium
        case .low: return low
        }
    }

    func borderColor(high: Color, medium: Color, low: Color) -> Color {
        switch self {
        case .high: return high.opacity(0.72)
        case .normal: return medium.opacity(0.72)
        case .low: return low.opacity(0.72)
        }
    }
}

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
            HStack(spacing: 8) {
                Button(action: onCancel) {
                    Image(systemName: "arrow.left")
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Zurück")
                .help("Neues To-Do abbrechen")
                Text(isNew ? "Neues To-Do" : "To-Do bearbeiten").font(.headline)
            }
            TextField("Titel", text: $todo.title).textFieldStyle(.roundedBorder)
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
                        .background(todo.repeatDays.contains(day) ? Color.accentColor : Color.secondary.opacity(0.15), in: RoundedRectangle(cornerRadius: 7))
                        .foregroundStyle(todo.repeatDays.contains(day) ? .white : .primary)
                        .accessibilityLabel("\(day.shortLabel) \(todo.repeatDays.contains(day) ? "ausgewählt" : "nicht ausgewählt")")
                    }
                }
            }
            HStack {
                Button("Abbrechen", action: onCancel)
                Spacer()
                Button("Speichern") {
                    todo.due = hasDue ? date : nil
                    switch priorityChoice {
                    case .standard(let priority):
                        todo.priority = priority
                        todo.customPriorityID = nil
                    case .custom(let id):
                        todo.customPriorityID = id
                    }
                    onSave(todo)
                }
                    .buttonStyle(.borderedProminent)
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
