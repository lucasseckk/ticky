import SwiftUI
import AppKit
import ServiceManagement

struct SettingsView: View {
    @ObservedObject var store: Store
    @ObservedObject var dev: DevStore
    let onClose: () -> Void
    @AppStorage("settingsTab") private var selectedTab = 0
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var launchHint: String?
    @AppStorage("globalShortcut") private var globalShortcut = true
    @AppStorage("showInDock") private var showInDock = true
    @AppStorage("showDev") private var showDev = DevStore.enabledByDefault
    @AppStorage(DevStore.agentDoneHoursKey) private var agentDoneHours = DevStore.agentDoneHoursDefault
    @AppStorage("manualSort") private var manualSort = false
    @AppStorage("highPriorityColor") private var highPriorityColorHex = "#C24033"
    @AppStorage("mediumPriorityColor") private var mediumPriorityColorHex = "#E0A63D"
    @AppStorage("lowPriorityColor") private var lowPriorityColorHex = "#94BD80"
    @AppStorage("priorityGlow") private var priorityGlow = true
    @AppStorage("notificationsEnabled") private var notificationsEnabled = false
    @AppStorage("notificationSound") private var notificationSound = true
    @AppStorage("animatedNotificationPopup") private var animatedNotificationPopup = true
    @AppStorage("highPriorityLeadMinutes") private var highPriorityLeadMinutes = 30
    @AppStorage("mediumPriorityLeadMinutes") private var mediumPriorityLeadMinutes = 120
    @AppStorage("lowPriorityReminderHour") private var lowPriorityReminderHour = 9
    @State private var notificationPermission: NotificationPermission?
    @State private var testResult: (text: String, success: Bool)?
    @State private var dataResult: (text: String, success: Bool)?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                IslandIconButton(systemImage: "arrow.left", label: String(localized: "Zurück zur To-Do-Liste"), action: onClose)
                Text("Einstellungen").font(.headline)
            }
            IslandSwitch(options: [(0, String(localized: "Allgemein"), nil), (1, String(localized: "Prioritäten"), nil), (2, String(localized: "Mitteilungen"), nil)], selection: $selectedTab)

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    switch selectedTab {
                    case 0: general
                    case 1: prioritiesAndGroups
                    default: notifications
                    }
                }
                .padding(.horizontal, 4)
                .padding(.bottom, 12)
            }
            .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .move(edge: .leading).combined(with: .opacity)))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .onChange(of: notificationSound) { _, _ in rescheduleNotifications() }
        .onChange(of: highPriorityLeadMinutes) { _, _ in rescheduleNotifications() }
        .onChange(of: mediumPriorityLeadMinutes) { _, _ in rescheduleNotifications() }
        .onChange(of: lowPriorityReminderHour) { _, _ in rescheduleNotifications() }
    }

    @ViewBuilder private var general: some View {
        SettingsCard(title: String(localized: "Start")) {
            SettingsToggle(title: String(localized: "Beim Anmelden starten"), isOn: Binding(get: { launchAtLogin }, set: { setLaunchAtLogin($0) }))
            SettingsToggle(title: String(localized: "Im Dock anzeigen"), isOn: $showInDock)
                .onChange(of: showInDock) { _, visible in DockIcon.setVisible(visible) }
            SettingsRow(title: String(localized: "Panel überall öffnen")) {
                if globalShortcut { ShortcutRecorder() }
                Toggle("Panel überall öffnen", isOn: $globalShortcut).labelsHidden().toggleStyle(.switch).controlSize(.small)
                    .onChange(of: globalShortcut) { _, enabled in GlobalShortcut.setEnabled(enabled) }
            }
            if let launchHint {
                Text(launchHint).font(.caption).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
                Button("Anmeldeobjekte öffnen") { SMAppService.openSystemSettingsLoginItems() }
            }
        }
        SettingsCard(title: String(localized: "Sortierung"), footer: manualSort ? String(localized: "Reihenfolge per Ziehen am Griff ≡.") : String(localized: "Offene zuerst, dann Priorität und Fälligkeit.")) {
            IslandSwitch(options: [(false, String(localized: "Automatisch"), nil), (true, String(localized: "Manuell"), nil)], selection: $manualSort)
        }
        SettingsCard(title: String(localized: "Dev-Bereich"), footer: String(localized: "Pull Requests und Agent-Aufgaben über die GitHub CLI (gh).")) {
            SettingsToggle(title: String(localized: "Dev-Bereich anzeigen"), isOn: $showDev)
            SettingsRow(title: String(localized: "Erledigte Agent-Aufgaben zeigen")) {
                Picker("Erledigte Agent-Aufgaben zeigen", selection: $agentDoneHours) {
                    Text("Nicht").tag(0)
                    Text("24 Stunden").tag(24)
                    Text("48 Stunden").tag(48)
                    Text("1 Woche").tag(168)
                }
                .labelsHidden()
                .fixedSize()
            }
        }
        SettingsCard(title: String(localized: "Daten"), footer: String(localized: "Sicherung als lesbare JSON-Datei. Vor jedem Import wird automatisch gesichert.")) {
            SettingsRow(title: String(localized: "Sicherung")) {
                Button("Exportieren …", action: exportBackup)
                Button("Importieren …", action: importBackup)
            }
            if let dataResult { resultLabel(dataResult) }
        }
        HStack {
            Text(appVersion)
            Spacer()
            Text("Alle Kürzel: ⌘/")
            Button("Beenden") { NSApp.terminate(nil) }
                .buttonStyle(.link)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 6)
    }

    @ViewBuilder private var prioritiesAndGroups: some View {
        SettingsCard(title: String(localized: "Prioritäten"), footer: String(localized: "Eigene Stufen 4–5 erinnern wie Hoch, 2–3 wie Mittel, 1 wie Niedrig.")) {
            SettingsToggle(title: String(localized: "Farbiger Glanz auf Karten"), isOn: $priorityGlow)
            Divider().opacity(0.5)
            ColorRow(label: String(localized: "Hoch"), hex: $highPriorityColorHex) { reminderPicker($highPriorityLeadMinutes) }
            ColorRow(label: String(localized: "Mittel"), hex: $mediumPriorityColorHex) { reminderPicker($mediumPriorityLeadMinutes) }
            ColorRow(label: String(localized: "Niedrig"), hex: $lowPriorityColorHex) {
                Picker("Erinnerung", selection: $lowPriorityReminderHour) {
                    ForEach(6...22, id: \.self) { hour in Text(String(localized: "täglich \(String(format: "%02d:00", hour))")).tag(hour) }
                }
                .labelsHidden().fixedSize()
            }
            ForEach(store.customPriorities) { priority in
                ColorRow(label: priority.name, hex: customPriorityColorBinding(for: priority.id)) {
                    Picker("Stufe", selection: customPriorityLevelBinding(for: priority.id)) {
                        ForEach(1...5, id: \.self) { Text("Stufe \($0)").tag($0) }
                    }
                    .labelsHidden().fixedSize()
                    DeleteButton(name: priority.name) { store.deleteCustomPriority(priority) }
                }
            }
            HStack {
                TextField("Neue Priorität", text: $newPriorityName)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(createPriority)
                Picker("Stufe", selection: $newPriorityThreatLevel) {
                    ForEach(1...5, id: \.self) { Text("Stufe \($0)").tag($0) }
                }
                .labelsHidden().fixedSize()
                AddButton(disabled: newPriorityName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, action: createPriority)
            }
            Button("Standardfarben wiederherstellen") {
                highPriorityColorHex = "#C24033"
                mediumPriorityColorHex = "#E0A63D"
                lowPriorityColorHex = "#94BD80"
            }
            .buttonStyle(.link)
            .font(.caption)
        }
        SettingsCard(title: String(localized: "Gruppen"), footer: String(localized: "Gruppen bündeln To-Dos mit gemeinsamen Notizen.")) {
            ForEach(store.groups) { group in
                ColorRow(label: group.name, hex: groupColorBinding(for: group.id)) {
                    DeleteButton(name: group.name) { store.deleteGroup(group) }
                }
            }
            HStack {
                TextField("Neue Gruppe", text: $newGroupName)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(createGroup)
                AddButton(disabled: newGroupName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, action: createGroup)
            }
        }
    }

    @ViewBuilder private var notifications: some View {
        SettingsCard(title: String(localized: "Mitteilungen"), footer: String(localized: "Wann erinnert wird, stellst du pro Priorität ein.")) {
            Label(notificationStatus.text, systemImage: notificationStatus.icon)
                .font(.callout.weight(.medium))
                .foregroundStyle(notificationStatus.color)
            if notificationPermission == .denied {
                Button("Mitteilungen in Systemeinstellungen öffnen") {
                    guard let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings") else { return }
                    NSWorkspace.shared.open(url)
                }
            }
            SettingsToggle(title: String(localized: "Mitteilungen senden"), isOn: $notificationsEnabled)
                .onChange(of: notificationsEnabled) { _, enabled in
                    if enabled {
                        NotificationManager.shared.requestAuthorization { _ in
                            DispatchQueue.main.async { refreshNotificationPermission() }
                        }
                    } else {
                        rescheduleNotifications()
                    }
                }
            SettingsToggle(title: String(localized: "Ton abspielen"), isOn: $notificationSound)
            SettingsToggle(title: String(localized: "Pop-up beim Klick auf eine Mitteilung"), isOn: $animatedNotificationPopup)
            SettingsRow(title: String(localized: "Test")) {
                Button("Senden") {
                    testResult = (String(localized: "Wird gesendet …"), true)
                    NotificationManager.shared.sendTestNotification { error in
                        DispatchQueue.main.async {
                            testResult = error.map { ($0, false) } ?? (String(localized: "Gesendet – erscheint in etwa 1 Sekunde."), true)
                            refreshNotificationPermission()
                        }
                    }
                }
            }
            if let testResult { resultLabel(testResult) }
        }
        .onAppear { refreshNotificationPermission() }
    }

    private func resultLabel(_ result: (text: String, success: Bool)) -> some View {
        Label(result.text, systemImage: result.success ? "checkmark.circle.fill" : "xmark.octagon.fill")
            .font(.caption)
            .foregroundStyle(result.success ? Color.green : Color.red)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func reminderPicker(_ selection: Binding<Int>) -> some View {
        Picker("Erinnerung", selection: selection) {
            Text("5 Min. vorher").tag(5)
            Text("15 Min. vorher").tag(15)
            Text("30 Min. vorher").tag(30)
            Text("1 Std. vorher").tag(60)
            Text("2 Std. vorher").tag(120)
            Text("1 Tag vorher").tag(1440)
        }
        .labelsHidden()
        .fixedSize()
    }

    @State private var newGroupName = ""
    @State private var newPriorityName = ""
    @State private var newPriorityThreatLevel = 3

    /// Version from Info.plist; `swift run` has no bundle version, hence the fallback (#64).
    private var appVersion: String {
        let info = Bundle.main.infoDictionary
        guard let version = info?["CFBundleShortVersionString"] as? String else { return String(localized: "Ticky · Entwicklungsversion") }
        let build = info?["CFBundleVersion"] as? String
        return String(localized: "Ticky · Version \(version)") + (build.map { " (\($0))" } ?? "")
    }

    /// Opt-in only: registers or removes the app as login item via the system, no helper app left behind.
    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            launchHint = nil
        } catch {
            launchHint = String(localized: "Nicht geändert: \(error.localizedDescription)")
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
        if SMAppService.mainApp.status == .requiresApproval {
            launchHint = String(localized: "macOS wartet auf deine Zustimmung unter Systemeinstellungen → Allgemein → Anmeldeobjekte.")
        }
    }

    private func exportBackup() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = String(localized: "Ticky-Sicherung \(Date().formatted(.iso8601.year().month().day())).json")
        panel.allowedContentTypes = [.json]
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            // Only the file itself: the chosen folder belongs to the user.
            try store.exportData().write(to: url, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
            dataResult = (String(localized: "Exportiert: \(url.lastPathComponent)"), true)
        } catch {
            dataResult = (String(localized: "Export fehlgeschlagen: \(error.localizedDescription)"), false)
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
            dataResult = (String(localized: "Importiert. Vorheriger Stand gesichert in Backups/\(safety.lastPathComponent)"), true)
        } catch {
            dataResult = (String(localized: "Nichts geändert – \(error.localizedDescription)"), false)
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

    private func customPriorityLevelBinding(for id: UUID) -> Binding<Int> {
        Binding(
            get: { store.customPriorities.first(where: { $0.id == id })?.threatLevel ?? 3 },
            set: { level in
                guard var priority = store.customPriorities.first(where: { $0.id == id }) else { return }
                priority.threatLevel = level
                store.updateCustomPriority(priority)
                rescheduleNotifications()
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
        case nil: return (String(localized: "Status wird geprüft …"), "hourglass", .secondary)
        case .denied: return (String(localized: "Von macOS blockiert"), "bell.slash.fill", .red)
        case .notDetermined: return (String(localized: "Noch nicht erlaubt – wird beim Einschalten abgefragt"), "bell.badge", .orange)
        case .allowed: return notificationsEnabled
            ? (String(localized: "Aktiv – Erinnerungen werden geplant"), "bell.fill", .green)
            : (String(localized: "Erlaubt, aber ausgeschaltet"), "bell", .secondary)
        }
    }

}

/// A titled group of settings rows; the optional footer is one short line (#107).
struct SettingsCard<Content: View>: View {
    let title: String
    var footer: String?
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6)
            VStack(alignment: .leading, spacing: 10) { content }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .islandSurface(cornerRadius: 14)
            if let footer {
                Text(footer)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .padding(.horizontal, 6)
            }
        }
    }
}

/// Label on the left, control on the right, like macOS System Settings.
struct SettingsRow<Control: View>: View {
    let title: String
    @ViewBuilder let control: Control

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
            Spacer(minLength: 8)
            control
        }
        .frame(minHeight: 24)
    }
}

struct SettingsToggle: View {
    let title: String
    @Binding var isOn: Bool

    var body: some View {
        SettingsRow(title: title) {
            Toggle(title, isOn: $isOn).labelsHidden().toggleStyle(.switch).controlSize(.small)
        }
    }
}

struct DeleteButton: View {
    let name: String
    let action: () -> Void

    var body: some View {
        Button(action: action) { Image(systemName: "trash") }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .accessibilityLabel("\(name) löschen")
            .help("\(name) löschen")
    }
}

struct AddButton: View {
    let disabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) { Image(systemName: "plus") }
            .buttonStyle(.borderedProminent)
            .disabled(disabled)
            .accessibilityLabel("Anlegen")
    }
}

/// Name with its color swatch on the left and its other settings on the right; the palette opens inline below,
/// because the panel sits at the right screen edge where a popover has no room.
struct ColorRow<Accessory: View>: View {
    let label: String
    @Binding var hex: String
    @ViewBuilder let accessory: Accessory
    @State private var showingPicker = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Button {
                    withAnimation(.easeOut(duration: 0.15)) { showingPicker.toggle() }
                } label: {
                    Circle()
                        .fill(Color(hex: hex))
                        .frame(width: 16, height: 16)
                        .overlay(Circle().stroke(Color.white.opacity(showingPicker ? 0.9 : 0.25), lineWidth: showingPicker ? 2 : 1))
                        .padding(2)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Farbe für \(label) ändern")
                .help("Farbe ändern")
                Text(label).lineLimit(1)
                Spacer(minLength: 8)
                accessory
            }
            .frame(minHeight: 24)
            if showingPicker {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 22))], spacing: 8) {
                    ForEach(colorPalette, id: \.self) { colorHex in
                        Button {
                            hex = colorHex
                            withAnimation(.easeOut(duration: 0.15)) { showingPicker = false }
                        } label: {
                            Circle()
                                .fill(Color(hex: colorHex))
                                .frame(width: 22, height: 22)
                                .overlay(Circle().stroke(Color.white.opacity(hex == colorHex ? 0.9 : 0.2), lineWidth: hex == colorHex ? 2.5 : 1))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Farbe \(colorHex)")
                    }
                }
                .padding(10)
                .background(.foreground.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }
}

private let colorPalette = [

    "#FFFFFF", "#F2F2F2", "#D9D9D9", "#808080", "#333333", "#000000",
    "#FF0000", "#C24033", "#FF7A59", "#FFB000", "#E0A63D", "#FFE066",
    "#94BD80", "#34A853", "#00A878", "#5BC0EB", "#2F80ED", "#6C5CE7",
    "#B36BCE", "#F29BB2", "#8B5E3C"
]

/// Click, then press the new shortcut; Esc cancels (#110).
struct ShortcutRecorder: View {
    @State private var label = GlobalShortcut.label
    @State private var monitor: Any?
    @State private var rejected = false

    var body: some View {
        HStack(spacing: 6) {
            if label != GlobalShortcut.label(modifiers: GlobalShortcut.defaultKey.modifiers, key: GlobalShortcut.defaultKey.key) && monitor == nil {
                Button {
                    GlobalShortcut.reset()
                    label = GlobalShortcut.label
                } label: { Image(systemName: "arrow.counterclockwise") }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Auf \(GlobalShortcut.label(modifiers: GlobalShortcut.defaultKey.modifiers, key: GlobalShortcut.defaultKey.key)) zurücksetzen")
            }
            Button(monitor == nil ? label : rejected ? String(localized: "Mit ⌘, ⌃ oder ⌥") : String(localized: "Kürzel drücken …")) {
                monitor == nil ? start() : stop()
            }
            .monospacedDigit()
            .help("Klicken und neues Kürzel drücken, Esc bricht ab")
        }
        .onDisappear(perform: stop)
    }

    private func start() {
        rejected = false
        GlobalShortcut.setEnabled(false)
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            MainActor.assumeIsolated {
                if event.keyCode == 53 { stop(); return }  // Esc
                guard let modifiers = GlobalShortcut.carbonModifiers(event.modifierFlags) else { rejected = true; return }
                GlobalShortcut.save(keyCode: event.keyCode, modifiers: modifiers, key: Self.keyName(event))
                label = GlobalShortcut.label
                stop()
            }
            return nil
        }
    }

    private func stop() {
        guard let monitor else { return }
        NSEvent.removeMonitor(monitor)
        self.monitor = nil
        rejected = false
        GlobalShortcut.setEnabled(UserDefaults.standard.object(forKey: "globalShortcut") as? Bool ?? true)
    }

    private static func keyName(_ event: NSEvent) -> String {
        switch event.keyCode {
        case 49: return String(localized: "Leertaste")
        case 36: return "↩"
        case 48: return "⇥"
        case 123: return "←"
        case 124: return "→"
        case 125: return "↓"
        case 126: return "↑"
        default:
            let text = event.charactersIgnoringModifiers?.uppercased() ?? ""
            return text.unicodeScalars.allSatisfy({ $0.properties.isAlphabetic || $0.properties.numericType != nil || $0.properties.isPatternSyntax })
                && !text.isEmpty ? text : String(localized: "Taste \(event.keyCode)")
        }
    }
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
