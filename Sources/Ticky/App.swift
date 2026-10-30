import SwiftUI
import AppKit

@main struct TickyApp: App {
    @NSApplicationDelegateAdaptor(NotificationAppDelegate.self) private var appDelegate
    @StateObject private var store: Store
    @StateObject private var dev = DevStore()
    init() {
        migratePreviousSettings()
        let store = Store()
        _store = StateObject(wrappedValue: store)
        NotificationManager.shared.store = store
    }
    var body: some Scene {
        MenuBarExtra {
            Panel(store: store, dev: dev)
        } label: {
            Image(nsImage: ClockIcon.menuImage(completed: store.count == 0))
                .accessibilityLabel("Ticky: \(store.count) offene To-Dos")
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
    @ObservedObject var dev: DevStore
    @State private var panelVisible = false
    @State private var title = ""
    @State private var statusFilter = StatusFilter.open
    @State private var filter = TodoFilter()
    @State private var showSearch = false
    @FocusState private var searchFocused: Bool
    /// Remembered, so the panel reopens where it was left (#16).
    @AppStorage("showSettings") private var showSettings = false
    @ObservedObject private var reminders = NotificationManager.shared
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
    @FocusState private var focusedCard: UUID?
    @AppStorage("dueView") private var dueView = false
    @AppStorage("panelSection") private var section = PanelSection.todos
    @AppStorage("showDev") private var showDev = DevStore.enabledByDefault
    @State private var showShortcuts = false
    @AppStorage("manualSort") private var manualSort = false
    @State private var dragLocation = CGPoint.zero
    @AppStorage("highPriorityColor") private var highPriorityColorHex = "#C24033"
    @AppStorage("mediumPriorityColor") private var mediumPriorityColorHex = "#E0A63D"
    @AppStorage("lowPriorityColor") private var lowPriorityColorHex = "#94BD80"
    private var highPriorityColor: Color { Color(hex: highPriorityColorHex) }
    private var mediumPriorityColor: Color { Color(hex: mediumPriorityColorHex) }
    private var lowPriorityColor: Color { Color(hex: lowPriorityColorHex) }
    private var items: [Todo] {
        let manualOrder = Dictionary(uniqueKeysWithValues: store.todos.enumerated().map { ($1.id, $0) })
        return store.todos.filter { !$0.isDev && (showArchive ? $0.showsInArchive : !$0.archived) && filter.matches($0) && (showArchive || matchesStatus($0)) }.sorted {
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
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 6) {
                statusPill
                Spacer(minLength: 4)
                if (section == .todos || !showDev) && !showSettings && draft == nil {
                    IslandIconButton(systemImage: "magnifyingglass", isOn: showSearch, label: showSearch ? String(localized: "Suche schließen") : String(localized: "To-Dos suchen und filtern"), action: toggleSearch)
                    IslandIconButton(systemImage: "archivebox", isOn: showArchive, label: showArchive ? String(localized: "Zurück zur Liste") : String(localized: "Archiv erledigter To-Dos")) {
                        withAnimation(.island) { showArchive.toggle(); confirmClearArchive = false }
                    }
                    IslandIconButton(systemImage: "calendar", isOn: dueView, label: dueView ? String(localized: "Nach Gruppen anzeigen") : String(localized: "Nach Fälligkeit anzeigen: Überfällig, Heute, Morgen …")) {
                        withAnimation(.island) { dueView.toggle() }
                    }
                }
                IslandIconButton(systemImage: "gearshape", isOn: showSettings, label: String(localized: "Einstellungen")) {
                    withAnimation(.island) { showSettings.toggle() }
                }
            }
            if !showSettings && draft == nil && showDev {
                IslandSwitch(options: PanelSection.allCases.map { ($0, $0.label, $0.systemImage) }, selection: $section)
            }
            if showSettings {
                SettingsView(store: store, dev: dev, onClose: { withAnimation(.island) { showSettings = false } })
            } else if section == .dev && showDev {
                DevView(dev: dev, store: store)
            } else {
            if draft == nil {
                Button(action: openNewEditor) {
                    HStack {
                        Text(title.isEmpty ? String(localized: "Was steht an?") : title)
                            .foregroundStyle(title.isEmpty ? .secondary : .primary)
                        Spacer()
                        Image(systemName: "plus")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(.black)
                            .frame(width: 26, height: 26)
                            .background(Color.white, in: Circle())
                    }
                    .padding(.leading, 16)
                    .padding(.trailing, 6)
                    .frame(maxWidth: .infinity, minHeight: 40, maxHeight: 40)
                    .islandCapsule()
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Neues To-Do anlegen")
                .keyboardShortcut("n", modifiers: .command)
                .help("Neues To-Do (⌘N)")
            }
            if let error = store.error { Text(error).font(.caption).foregroundStyle(.red).textSelection(.enabled) }
            if let problem = reminders.plan.problem { Label(problem, systemImage: "bell.slash").font(.caption).foregroundStyle(.red).textSelection(.enabled) }
            if let todo = draft {
                ScrollView {
                    Editor(todo: todo, isNew: draftIsNew, groups: store.groups, customPriorities: store.customPriorities, onSave: saveDraft, onCancel: { withAnimation(.island) { draft = nil } }).id(todo.id)
                }
            } else {
                if showSearch { filterBar }
                ScrollView {
                    LazyVStack(spacing: 8) {
                        if showArchive { archiveHeader }
                        if items.isEmpty {
                            VStack(spacing: 10) {
                                Image(systemName: filterActive ? "magnifyingglass" : showArchive ? "archivebox" : "checkmark.seal").font(.system(size: 34))
                                Text(filterActive ? String(localized: "Keine passenden To-Dos.") : showArchive ? String(localized: "Das Archiv ist leer.") : String(localized: "Platz für deinen nächsten Plan."))
                            }.foregroundStyle(.secondary).frame(maxWidth: .infinity).padding(.vertical, 40)
                        }
                        if showArchive {
                            ForEach(items) { item in todoCard(item) }
                        } else if dueView {
                            ForEach(DueBucket.allCases) { bucket in dueSection(bucket) }
                        } else {
                        VStack(spacing: 8) {
                            ForEach(standardItems) { item in todoCard(item) }
                            if standardItems.isEmpty && draggingTodoID != nil {
                                Text("To-Dos hierher ziehen, um sie aus einer Gruppe zu lösen.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity, minHeight: 68)
                            }
                        }
                        .contentShape(Rectangle())
                        .background(Color.white.opacity(hoveringStandard ? 0.06 : 0), in: RoundedRectangle(cornerRadius: 14))
                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(hoveringStandard ? 0.4 : 0), lineWidth: 1.5))
                        .background(GeometryReader { proxy in
                            Color.clear.preference(key: StandardFramePreferenceKey.self, value: proxy.frame(in: .named("todo-list")))
                        })
                        ForEach(visibleGroups) { group in groupBlock(group) }
                        }
                    }
                    // Room for the card glow, which the scroll view would otherwise clip.
                    .padding(.horizontal, 4)
                    .padding(.vertical, 8)
                }
                .coordinateSpace(name: "todo-list")
                .frame(minHeight: 160, maxHeight: .infinity)
                .onPreferenceChange(GroupFramePreferenceKey.self) { groupFrames = $0 }
                .onPreferenceChange(CardFramePreferenceKey.self) { cardFrames = $0 }
                .onPreferenceChange(StandardFramePreferenceKey.self) { standardFrame = $0 }
                .safeAreaInset(edge: .bottom) {
                    if !showArchive, store.archivableCount > 0 {
                        Button { withAnimation(.island) { store.archiveDone() } } label: {
                            Label("\(store.archivableCount) erledigte archivieren", systemImage: "archivebox")
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(Color.black, in: Capsule())
                                .overlay(Capsule().strokeBorder(Color.white.opacity(0.15)))
                        }
                        .buttonStyle(.plain)
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
        .animation(.island, value: store.undoStep?.id)
        .overlay {
            if showShortcuts { ShortcutOverlay { withAnimation(.island) { showShortcuts = false } } }
        }
        .background {
            Button("Tastenkürzel") { withAnimation(.island) { showShortcuts.toggle() } }
                .keyboardShortcut("/", modifiers: .command)
                .hidden()
        }
        .padding(18)
        // Always the same height: if the menu bar window resizes, macOS moves it away from the menu bar.
        .frame(width: 460, height: 560, alignment: .top)
        .background(Color.black)
        .environment(\.colorScheme, .dark)
        .opacity(panelVisible ? 1 : 0)
        .scaleEffect(panelVisible ? 1 : 0.94, anchor: .top)
        .onAppear {
            withAnimation(.island) { panelVisible = true }
            rescheduleNotifications()
        }
    }
    private var overdueCount: Int { store.overdueCount }
    private var statusPill: some View {
        HStack(spacing: 6) {
            Circle().fill(Color.white.opacity(store.count == 0 ? 0.35 : 0.9)).frame(width: 6, height: 6)
            Text(store.count == 0 ? String(localized: "Alles erledigt") : String(localized: "\(store.count) offen"))
            Group {
                if overdueCount > 0 { Text("· \(overdueCount) überfällig") }
                if showDev && !dev.pullRequests(in: .review).isEmpty {
                    let reviews = dev.pullRequests(in: .review).count
                    Text(reviews == 1 ? String(localized: "· 1 PR wartet") : String(localized: "· \(reviews) PRs warten"))
                }
            }
            .foregroundStyle(.secondary)
        }
        .font(.callout.weight(.semibold))
        .lineLimit(1)
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(Color.black, in: Capsule())
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.12)))
        .accessibilityElement(children: .combine)
    }
    private func undoBar(_ step: UndoStep) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "arrow.uturn.backward.circle.fill").foregroundStyle(.secondary)
            Text(step.label).lineLimit(1)
            Spacer(minLength: 8)
            Button("Rückgängig") {
                withAnimation(.island) { store.undo() }
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
        .background(Color.black, in: Capsule())
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.15)))
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .task(id: step.id) {
            try? await Task.sleep(for: .seconds(8))
            store.dismissUndo(step.id)
        }
    }
    private func openNewEditor() {
        draftIsNew = true
        withAnimation(.island) { draft = Todo(title: title) }
    }
    private func toggleSearch() {
        withAnimation(.island) {
            showSearch.toggle()
            // Closed search must not leave invisible filters behind.
            if !showSearch { resetFilter() }
        }
        searchFocused = showSearch
    }
    private var filterBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("To-Dos suchen", text: $filter.query)
                        .textFieldStyle(.plain)
                        .focused($searchFocused)
                        .onExitCommand(perform: toggleSearch)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .islandCapsule()
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
            presetRow(String(localized: "Schnell")) {
                presetChip(String(localized: "Überfällig"), "exclamationmark.circle", filter.due == .overdue) { filter.due = filter.due == .overdue ? .all : .overdue }
                presetChip(String(localized: "Heute"), "calendar", filter.due == .today) { filter.due = filter.due == .today ? .all : .today }
                presetChip(String(localized: "Ohne Datum"), "calendar.badge.minus", filter.due == DueFilter.none) { filter.due = filter.due == DueFilter.none ? .all : DueFilter.none }
                presetChip(String(localized: "Erledigt"), "checkmark.circle", statusFilter == .done) { statusFilter = statusFilter == .done ? .open : .done }
            }
            presetRow(String(localized: "Priorität")) {
                ForEach(Priority.allCases.reversed()) { priority in
                    priorityChip(priority.label, .standard(priority))
                }
            }
            presetRow(String(localized: "Eigene")) {
                ForEach(store.customPriorities) { priority in
                    priorityChip(priority.name, .custom(priority.id))
                }
                if store.customPriorities.isEmpty {
                    presetChip(String(localized: "Eigene Priorität anlegen"), "plus", false) { showSettings = true }
                }
            }
            presetRow(String(localized: "Gruppe")) {
                presetChip(String(localized: "Ohne Gruppe"), "tray", filter.group == .ungrouped) { filter.group = filter.group == .ungrouped ? .all : .ungrouped }
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
                .foregroundStyle(isOn ? Color.black : Color.white.opacity(0.85))
                .background(isOn ? Color.white : Color.white.opacity(0.08), in: Capsule())
                .overlay(Capsule().strokeBorder(Color.white.opacity(isOn ? 0 : 0.1)))
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
                Button(confirmClearArchive ? String(localized: "Wirklich alle löschen?") : String(localized: "Archiv leeren")) {
                    if confirmClearArchive {
                        withAnimation(.island) { store.clearArchive() }
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
        let bucketItems = dueItems(bucket, now: now)
        if !bucketItems.isEmpty {
            HStack {
                Text(bucket.label).font(.headline)
                Text("\(bucketItems.count)").font(.caption).foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.top, 8)
            .padding(.horizontal, 4)
            ForEach(bucketItems) { item in todoCard(item) }
        }
    }
    private func dueItems(_ bucket: DueBucket, now: Date) -> [Todo] {
        items.filter { DueBucket($0, now: now) == bucket }.sorted { ($0.due ?? .distantFuture) < ($1.due ?? .distantFuture) }
    }
    /// Cards in the order they are shown, for ↑/↓ (#6).
    private var displayOrder: [UUID] {
        if showArchive { return items.map(\.id) }
        if dueView { let now = Date(); return DueBucket.allCases.flatMap { dueItems($0, now: now) }.map(\.id) }
        return (standardItems + visibleGroups.flatMap { groupedItems(for: $0.id) }).map(\.id)
    }
    private func moveFocus(from id: UUID, by step: Int) -> KeyPress.Result {
        let order = displayOrder
        guard let index = order.firstIndex(of: id), order.indices.contains(index + step) else { return .ignored }
        focusedCard = order[index + step]
        return .handled
    }
    private var standardItems: [Todo] { items.filter { $0.groupID == nil } }
    private func groupedItems(for groupID: UUID) -> [Todo] { items.filter { $0.groupID == groupID } }
    @ViewBuilder private func groupBlock(_ group: TodoGroup) -> some View {
        let groupItems = groupedItems(for: group.id)
        let groupColor = Color(hex: group.colorHex)
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Circle().fill(groupColor).frame(width: 9, height: 9)
                Text(group.name).font(.headline)
                Text("\(groupItems.filter { !$0.done }.count)")
                    .font(.caption.weight(.bold))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 1)
                    .foregroundStyle(.secondary)
                    .background(Color.white.opacity(0.08), in: Capsule())
                Spacer()
                Image(systemName: "line.3.horizontal").foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.black, in: Capsule())
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.1)))
            .contentShape(Capsule())
            .help("Ziehen, um die Gruppe zu verschieben")
            .gesture(DragGesture(minimumDistance: 8, coordinateSpace: .named("todo-list"))
                .onChanged { value in
                    draggingGroupID = group.id
                    hoveredGroupID = groupFrames.first(where: { $0.key != group.id && $0.value.contains(value.location) })?.key
                }
                .onEnded { _ in
                    if let target = hoveredGroupID { withAnimation(.island) { store.reorderGroup(group.id, to: target) } }
                    draggingGroupID = nil
                    hoveredGroupID = nil
                })
            // Slim one-line notes bar that grows while typing.
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: "note.text").font(.caption).foregroundStyle(.secondary)
                TextField("Notizen", text: groupNotesBinding(for: group), axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.callout)
                    .lineLimit(1...6)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 14))
            VStack(spacing: 8) {
                ForEach(groupItems) { item in todoCard(item) }
                if groupItems.isEmpty {
                    Text("Noch keine To-Dos in dieser Gruppe.").font(.caption).foregroundStyle(.secondary).padding(.vertical, 4)
                }
            }
            .padding(.leading, 12)
        }
        .padding(8)
        .background(groupColor.opacity(hoveredGroupID == group.id ? 0.24 : 0.12), in: RoundedRectangle(cornerRadius: 22))
        .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(groupColor.opacity(hoveredGroupID == group.id ? 0.7 : 0.3), lineWidth: 1))
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
        HStack(alignment: .center, spacing: 10) {
            Button { withAnimation(.island) { store.toggle(item) }; rescheduleNotifications() } label: {
                Image(systemName: item.done ? "checkmark.circle.fill" : "circle").font(.title2)
                    .foregroundStyle(Color.white.opacity(item.done ? 0.5 : 0.85))
            }.buttonStyle(.plain).accessibilityLabel(item.done ? String(localized: "Wieder öffnen: \(item.title)") : String(localized: "Erledigen: \(item.title)"))
            VStack(alignment: .leading, spacing: 6) {
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
                    Text(item.title).font(.body.weight(.medium)).strikethrough(item.done).foregroundStyle(item.done ? .secondary : .primary)
                        .fixedSize(horizontal: false, vertical: true)
                        .onTapGesture(count: 2) { startEditingTitle(item) }
                        .help("Doppelklick zum Umbenennen")
                }
                infoPills(item)
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
                    Button("Wiederherstellen") { withAnimation(.island) { store.setArchived(item.id, false) } }
                } else if item.canArchive {
                    Button("Archivieren") { withAnimation(.island) { store.setArchived(item.id, true) } }
                }
                Divider()
                Button("Löschen", role: .destructive) { withAnimation(.island) { store.delete(item) }; rescheduleNotifications() }
            } label: { Image(systemName: "ellipsis").font(.system(size: 12, weight: .bold)) }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
            .frame(width: 28, height: 28)
            .background(Color.white.opacity(0.12), in: Circle())
            .accessibilityLabel("Optionen für \(item.title)")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(minHeight: 56)
        .islandCard(stripe: cardColor(for: item))
        .overlay(alignment: .top) {
            if hoveredCardID == item.id {
                Capsule().fill(Color.white).frame(height: 2).offset(y: -5)
            }
        }
        .opacity(draggingTodoID == item.id ? 0.28 : (item.done ? 0.55 : 1))
        .contentShape(RoundedRectangle(cornerRadius: 16))
        // Keyboard: ↑/↓ move between cards, Return renames, Space checks off (#6).
        .focusable(editingTodoID != item.id)
        .focused($focusedCard, equals: item.id)
        .focusEffectDisabled()
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.white.opacity(focusedCard == item.id ? 0.6 : 0), lineWidth: 1.5))
        .onKeyPress(.upArrow) { moveFocus(from: item.id, by: -1) }
        .onKeyPress(.downArrow) { moveFocus(from: item.id, by: 1) }
        .onKeyPress(.return) { startEditingTitle(item); return .handled }
        .onKeyPress(.space) {
            withAnimation(.island) { store.toggle(item) }
            rescheduleNotifications()
            return .handled
        }
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
                    withAnimation(.island) { store.reorderTodo(item.id, to: target) }
                } else if (groupID != nil || isStandardDrop), groupID != item.groupID {
                    withAnimation(.island) { store.moveTodo(item.id, to: groupID) }
                    rescheduleNotifications()
                }
                draggingTodoID = nil
                hoveredCardID = nil
                hoveredGroupID = nil
                hoveringStandard = false
            })
        .transition(.asymmetric(insertion: .scale(scale: 0.55, anchor: .top).combined(with: .move(edge: .top)).combined(with: .opacity), removal: .opacity))
    }
    @ViewBuilder private func infoPills(_ item: Todo) -> some View {
        let group = (dueView || showArchive) ? store.groups.first(where: { $0.id == item.groupID }) : nil
        let snoozed = item.snoozedUntil.flatMap { $0 > Date() && !item.done ? $0 : nil }
        if item.due != nil || item.repeatRule != .none || group != nil || snoozed != nil {
            HStack(spacing: 5) {
                if let snoozed { InfoPill(text: String(localized: "später \(snoozed.formatted(date: .omitted, time: .shortened))"), systemImage: "moon.zzz") }
                if let due = item.due {
                    // Overdue is marked by symbol and word, not only by red, so it stays clear on every card color.
                    if !item.done && due < Date() {
                        InfoPill(text: String(localized: "Überfällig · \(due.formatted(.dateTime.day().month().hour().minute()))"), systemImage: "exclamationmark.triangle.fill", tint: .red)
                            .fontWeight(.bold)
                    } else {
                        InfoPill(text: due.formatted(.dateTime.day().month().hour().minute()), systemImage: "calendar")
                    }
                    if item.extraReminder != .none { InfoPill(text: item.extraReminder.label.replacingOccurrences(of: String(localized: " vorher"), with: ""), systemImage: "bell") }
                }
                if item.repeatRule != .none { InfoPill(text: item.repeatRule.label, systemImage: "repeat") }
                if let group { InfoPill(text: group.name, systemImage: "folder", tint: Color(hex: group.colorHex)) }
            }
        }
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
                withAnimation(.island) { store.save(todo) }
                rescheduleNotifications()
            }
        )
    }
    private func groupBinding(for item: Todo) -> Binding<UUID?> {
        Binding(
            get: { item.groupID },
            set: { groupID in
                withAnimation(.island) { store.moveTodo(item.id, to: groupID) }
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
        .islandCard(stripe: cardColor(for: item))
        .opacity(0.75)
        .shadow(color: .black.opacity(0.18), radius: 8, y: 4)
    }
    private func add() {
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        saveDraft(Todo(title: title))
    }
    private func saveDraft(_ todo: Todo) {
        withAnimation(.island) {
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

private extension Priority {
    func cardColor(high: Color, medium: Color, low: Color) -> Color {
        switch self {
        case .high: return high
        case .normal: return medium
        case .low: return low
        }
    }
}

