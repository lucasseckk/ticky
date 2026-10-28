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
    @AppStorage("manualSort") private var manualSort = false
    @AppStorage("highPriorityColor") private var highPriorityColorHex = "#C24033"
    @AppStorage("mediumPriorityColor") private var mediumPriorityColorHex = "#E0A63D"
    @AppStorage("lowPriorityColor") private var lowPriorityColorHex = "#94BD80"
    @AppStorage("priorityGlow") private var priorityGlow = true
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


    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                IslandIconButton(systemImage: "arrow.left", label: "Zurück zur To-Do-Liste", action: onClose)
                Text("Einstellungen").font(.headline)
            }
            IslandSwitch(options: [(0, "Allgemein", nil), (1, "Darstellung", nil), (2, "Mitteilungen", nil)], selection: $selectedTab)

            Group {
                if selectedTab == 0 {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) {
                            SettingsCard(title: "Start", systemImage: "power", subtitle: "Starten über Spotlight („Ticky“) oder das Dock, beenden per Rechtsklick aufs Dock-Icon oder hier. Autostart beim Anmelden ist optional und lässt sich jederzeit wieder entfernen.") {
                                Toggle("Beim Anmelden automatisch starten", isOn: Binding(get: { launchAtLogin }, set: setLaunchAtLogin))
                                Toggle("Panel überall mit \(GlobalShortcut.label) öffnen", isOn: $globalShortcut)
                                    .onChange(of: globalShortcut) { _, enabled in GlobalShortcut.setEnabled(enabled) }
                                Toggle("Im Dock anzeigen", isOn: $showInDock)
                                    .onChange(of: showInDock) { _, visible in DockIcon.setVisible(visible) }
                                Text("Im Panel: ⌘N neues To-do · ↑↓ zwischen Karten · Return umbenennen · Leertaste abhaken · Esc abbrechen")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                if let launchHint {
                                    Text(launchHint).font(.caption).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
                                    Button("Anmeldeobjekte in den Systemeinstellungen öffnen") { SMAppService.openSystemSettingsLoginItems() }
                                }
                                Button(role: .destructive) { NSApp.terminate(nil) } label: { Label("Ticky beenden", systemImage: "power") }
                            }
                            SettingsCard(title: "Sortierung", systemImage: "arrow.up.arrow.down", subtitle: manualSort
                                ? "Ziehe To-Dos auf andere To-Dos und Gruppen am Griff ≡, um die Reihenfolge festzulegen."
                                : "Offene zuerst, dann nach Priorität, Fälligkeit und Erstellung. Gruppen lassen sich immer am Griff ≡ verschieben.") {
                                IslandSwitch(options: [(false, "Automatisch", nil), (true, "Manuell", nil)], selection: $manualSort)
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
                            Text(appVersion)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity)
                        }
                        .padding(12)
                    }
                } else if selectedTab == 1 {
                    ScrollView(.vertical) {
                        VStack(alignment: .leading, spacing: 12) {
                            SettingsCard(title: "Prioritätsfarben", systemImage: "flag", subtitle: nil) {
                                Toggle("Farbiger Glanz auf Karten (sonst nur Streifen am Rand)", isOn: $priorityGlow)
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
                                ColorSettingRow(label: "Hoch", hex: $defaultHighHex)
                                ColorSettingRow(label: "Mittel", hex: $defaultMediumHex)
                                ColorSettingRow(label: "Niedrig", hex: $defaultLowHex)
                                Button("Auf Standard zurücksetzen") {
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
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    @State private var newGroupName = ""
    @State private var newPriorityName = ""
    @State private var newPriorityThreatLevel = 3

    /// Version from Info.plist; `swift run` has no bundle version, hence the fallback (#64).
    private var appVersion: String {
        let info = Bundle.main.infoDictionary
        guard let version = info?["CFBundleShortVersionString"] as? String else { return "Ticky · Entwicklungsversion" }
        let build = info?["CFBundleVersion"] as? String
        return "Ticky · Version \(version)" + (build.map { " (\($0))" } ?? "")
    }

    /// Opt-in only: registers or removes the app as login item via the system, no helper app left behind.
    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            launchHint = nil
        } catch {
            launchHint = "Nicht geändert: \(error.localizedDescription)"
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
        if SMAppService.mainApp.status == .requiresApproval {
            launchHint = "macOS wartet auf deine Zustimmung unter Systemeinstellungen → Allgemein → Anmeldeobjekte."
        }
    }

    private func exportBackup() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "Ticky-Sicherung \(Date().formatted(.iso8601.year().month().day())).json"
        panel.allowedContentTypes = [.json]
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            // Only the file itself: the chosen folder belongs to the user.
            try store.exportData().write(to: url, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
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
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .islandSurface(cornerRadius: 18)
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
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(Color.black, in: Capsule())
        .overlay(Capsule().strokeBorder(Color(hex: colorHex).opacity(0.4)))
    }
}

struct ColorSettingRow: View {
    let label: String
    @Binding var hex: String
    @State private var showingPicker = false

    var body: some View {
        // Inline instead of a popover: the panel sits at the right screen edge, where a popover has no room.
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(label)
                Spacer()
                Button {
                    withAnimation(.easeOut(duration: 0.15)) { showingPicker.toggle() }
                } label: {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(hex: hex))
                        .frame(width: 58, height: 28)
                        .overlay {
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.primary.opacity(showingPicker ? 0.9 : 0.35), lineWidth: showingPicker ? 2 : 1)
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Farbe für \(label) ändern")
            }
            if showingPicker {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 26))], spacing: 8) {
                    ForEach(Self.palette, id: \.self) { colorHex in
                        Button {
                            hex = colorHex
                            withAnimation(.easeOut(duration: 0.15)) { showingPicker = false }
                        } label: {
                            Circle()
                                .fill(Color(hex: colorHex))
                                .frame(width: 26, height: 26)
                                .overlay {
                                    Circle().stroke(Color.primary.opacity(hex == colorHex ? 0.9 : 0.25), lineWidth: hex == colorHex ? 3 : 1)
                                }
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
