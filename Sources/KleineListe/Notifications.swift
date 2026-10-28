import AppKit
import SwiftUI
import UserNotifications

final class NotificationAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NotificationManager.shared.configure()
    }
}

/// One source for banner and pop-up wording, so both always say the same thing.
enum NotificationKind: String {
    case test, dueSoon, overdue, daily

    var headline: String {
        switch self {
        case .test: return "Testmitteilung"
        case .dueSoon: return "Bald fällig"
        case .overdue: return "Jetzt fällig"
        case .daily: return "Täglicher Überblick"
        }
    }
    var symbol: String {
        switch self {
        case .test: return "👋"
        case .dueSoon: return "⏰"
        case .overdue: return "🚨"
        case .daily: return "☀️"
        }
    }
    var tint: Color {
        switch self {
        case .test: return .green
        case .dueSoon: return .orange
        case .overdue: return .red
        case .daily: return .blue
        }
    }
}

enum NotificationPermission {
    case allowed, denied, notDetermined
    init(_ status: UNAuthorizationStatus) {
        switch status {
        case .authorized, .provisional, .ephemeral: self = .allowed
        case .denied: self = .denied
        default: self = .notDetermined
        }
    }
}

final class NotificationManager: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {
    static let shared = NotificationManager()
    private let center = UNUserNotificationCenter.current()
    private let queue = DispatchQueue(label: "notification-scheduling")
    private var generation = 0
    /// Lets notification actions work without the panel ever being opened (#10).
    weak var store: Store?

    static let todoCategory = "todo"
    static let doneAction = "done"

    func configure() {
        center.delegate = self
        let actions = [UNNotificationAction(identifier: Self.doneAction, title: "Erledigen", options: [])]
            + Snooze.allCases.map { UNNotificationAction(identifier: "snooze-\($0.rawValue)", title: "Später: \($0.label)", options: []) }
        center.setNotificationCategories([UNNotificationCategory(identifier: Self.todoCategory, actions: actions, intentIdentifiers: [])])
    }

    func requestAuthorization(completion: @escaping @Sendable (Bool) -> Void) {
        center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in completion(granted) }
    }

    func permission(completion: @escaping @Sendable (NotificationPermission) -> Void) {
        center.getNotificationSettings { settings in completion(NotificationPermission(settings.authorizationStatus)) }
    }

    func reschedule(todos: [Todo], customPriorities: [CustomPriority]) {
        // Only the newest call may schedule; an older, slower call would otherwise re-add reminders for deleted or finished to-dos.
        let current = queue.sync { generation += 1; return generation }
        center.getNotificationSettings { [weak self] settings in
            guard let self else { return }
            self.queue.sync {
                guard current == self.generation else { return }
                self.center.removeAllPendingNotificationRequests()
                let openTodos = todos.filter { !$0.done || $0.repeatRule != .none }
                self.removeDelivered(keeping: Set(openTodos.map(\.id)))
                guard UserDefaults.standard.bool(forKey: "notificationsEnabled"),
                      NotificationPermission(settings.authorizationStatus) == .allowed else { return }
                self.scheduleAll(openTodos, customPriorities: customPriorities)
            }
        }
    }

    private func removeDelivered(keeping openIDs: Set<UUID>) {
        center.getDeliveredNotifications { [weak self] delivered in
            let stale = delivered.filter { notification in
                guard let id = UUID(uuidString: notification.request.content.userInfo["todoID"] as? String ?? "") else { return false }
                return !openIDs.contains(id)
            }
            self?.center.removeDeliveredNotifications(withIdentifiers: stale.map(\.request.identifier))
        }
    }

    private func scheduleAll(_ openTodos: [Todo], customPriorities: [CustomPriority]) {
        for todo in openTodos {
            schedule(todo: todo, customPriorities: customPriorities)
        }
        if openTodos.contains(where: { isLowPriority($0, customPriorities: customPriorities) }) {
            scheduleDailyLowPrioritySummary()
        }
    }

    func sendTestNotification(completion: @escaping @Sendable (String?) -> Void) {
        center.getNotificationSettings { [weak self] settings in
            guard let self else { return }
            if settings.authorizationStatus == .notDetermined {
                self.requestAuthorization { granted in
                    guard granted else {
                        completion("macOS-Benachrichtigungen wurden nicht erlaubt.")
                        return
                    }
                    self.enqueueTestNotification(completion: completion)
                }
            } else if settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional {
                self.enqueueTestNotification(completion: completion)
            } else {
                completion("macOS-Benachrichtigungen sind nicht erlaubt. Bitte in Systemeinstellungen > Mitteilungen für To-Do List aktivieren.")
            }
        }
    }

    private func enqueueTestNotification(completion: @escaping @Sendable (String?) -> Void) {
        let content = content(subtitle: NotificationKind.test.headline, body: "Deine Erinnerungen funktionieren.", kind: .test, todoID: nil, todoTitle: "Deine Erinnerungen funktionieren.")
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        center.add(UNNotificationRequest(identifier: "test-notification", content: content, trigger: trigger)) { error in
            completion(error?.localizedDescription)
        }
    }

    private func schedule(todo: Todo, customPriorities: [CustomPriority]) {
        // A snoozed reminder fires once more at the chosen time; the original ones are not repeated.
        if let until = todo.snoozedUntil, until > Date() {
            let content = content(subtitle: "Erinnerung · verschoben", body: "„\(todo.title)“ – du wolltest jetzt daran erinnert werden.", kind: .dueSoon, todoID: todo.id, todoTitle: todo.title)
            let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: until)
            center.add(UNNotificationRequest(identifier: "todo-\(todo.id)-snooze", content: content, trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false)))
        }
        guard let due = todo.due else { return }
        let leadMinutes = automaticLeadMinutes(for: todo, customPriorities: customPriorities)
        if let leadMinutes {
            add(todo: todo, fireDate: due.addingTimeInterval(TimeInterval(-leadMinutes * 60)), identifier: "lead", kind: .dueSoon, remainingMinutes: leadMinutes)
        }
        if todo.extraReminder != .none, todo.extraReminder.rawValue != leadMinutes {
            add(todo: todo, fireDate: due.addingTimeInterval(TimeInterval(-todo.extraReminder.rawValue * 60)), identifier: "extra", kind: .dueSoon, remainingMinutes: todo.extraReminder.rawValue)
        }
        add(todo: todo, fireDate: due, identifier: "due", kind: .overdue, remainingMinutes: 0)
    }

    private func automaticLeadMinutes(for todo: Todo, customPriorities: [CustomPriority]) -> Int? {
        let defaults = UserDefaults.standard
        if let customID = todo.customPriorityID, let custom = customPriorities.first(where: { $0.id == customID }) {
            if custom.threatLevel >= 4 { return defaults.integer(forKey: "highPriorityLeadMinutes").nonZero(or: 30) }
            if custom.threatLevel >= 2 { return defaults.integer(forKey: "mediumPriorityLeadMinutes").nonZero(or: 120) }
            return nil
        }
        switch todo.priority {
        case .high: return defaults.integer(forKey: "highPriorityLeadMinutes").nonZero(or: 30)
        case .normal: return defaults.integer(forKey: "mediumPriorityLeadMinutes").nonZero(or: 120)
        case .low: return nil
        }
    }

    private func isLowPriority(_ todo: Todo, customPriorities: [CustomPriority]) -> Bool {
        if let customID = todo.customPriorityID, let custom = customPriorities.first(where: { $0.id == customID }) {
            return custom.threatLevel == 1
        }
        return todo.priority == .low
    }

    private func add(todo: Todo, fireDate: Date, identifier: String, kind: NotificationKind, remainingMinutes: Int) {
        if todo.repeatRule == .none, fireDate <= Date() { return }
        let content = content(
            subtitle: kind == .overdue ? kind.headline : "\(kind.headline) · noch \(durationText(remainingMinutes))",
            body: kind == .overdue ? "„\(todo.title)“ ist jetzt fällig." : "„\(todo.title)“ ist in \(durationText(remainingMinutes)) fällig.",
            kind: kind,
            todoID: todo.id,
            todoTitle: todo.title
        )
        for (suffix, trigger) in triggers(for: fireDate, rule: todo.repeatRule, days: todo.repeatDays) {
            center.add(UNNotificationRequest(identifier: "todo-\(todo.id)-\(identifier)-\(suffix)", content: content, trigger: trigger))
        }
    }

    private func triggers(for date: Date, rule: RepeatRule, days: Set<Weekday>) -> [(String, UNNotificationTrigger)] {
        let calendar = Calendar.current
        switch rule {
        case .none:
            return [("once", UNCalendarNotificationTrigger(dateMatching: calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date), repeats: false))]
        case .daily:
            return [("daily", UNCalendarNotificationTrigger(dateMatching: calendar.dateComponents([.hour, .minute], from: date), repeats: true))]
        case .weekly:
            return [("weekly", UNCalendarNotificationTrigger(dateMatching: calendar.dateComponents([.weekday, .hour, .minute], from: date), repeats: true))]
        case .monthly:
            return [("monthly", UNCalendarNotificationTrigger(dateMatching: calendar.dateComponents([.day, .hour, .minute], from: date), repeats: true))]
        case .custom:
            let time = calendar.dateComponents([.hour, .minute], from: date)
            return days.map { day in
                var components = time
                components.weekday = day.calendarWeekday
                return ("weekday-\(day.rawValue)", UNCalendarNotificationTrigger(dateMatching: components, repeats: true))
            }
        }
    }

    private func scheduleDailyLowPrioritySummary() {
        var components = DateComponents()
        components.hour = UserDefaults.standard.integer(forKey: "lowPriorityReminderHour").nonZero(or: 9)
        components.minute = 0
        let content = content(subtitle: NotificationKind.daily.headline, body: "Du hast noch niedrig priorisierte To-Dos offen.", kind: .daily, todoID: nil, todoTitle: "Du hast noch niedrig priorisierte To-Dos offen.")
        center.add(UNNotificationRequest(identifier: "daily-low-priority-summary", content: content, trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: true)))
    }

    private func content(subtitle: String, body: String, kind: NotificationKind, todoID: UUID?, todoTitle: String) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = "To-Do List"
        content.subtitle = subtitle
        content.body = body
        if UserDefaults.standard.object(forKey: "notificationSound") as? Bool ?? true { content.sound = .default }
        content.userInfo = ["kind": kind.rawValue, "todoID": todoID?.uuidString ?? "", "todoTitle": todoTitle]
        if todoID != nil { content.categoryIdentifier = Self.todoCategory }
        return content
    }

    private func durationText(_ minutes: Int) -> String {
        if minutes == 1440 { return "1 Tag" }
        if minutes == 2880 { return "2 Tage" }
        if minutes == 60 { return "1 Stunde" }
        if minutes > 60, minutes.isMultiple(of: 60) { return "\(minutes / 60) Stunden" }
        return "\(minutes) Minuten"
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        let content = response.notification.request.content
        let todoID = UUID(uuidString: content.userInfo["todoID"] as? String ?? "")
        let action = response.actionIdentifier
        if let todoID, action == Self.doneAction || action.hasPrefix("snooze-") {
            let snooze = Snooze(rawValue: String(action.dropFirst("snooze-".count)))
            Task { @MainActor in
                guard let store = self.store else { return }
                if let snooze { store.snooze(todoID, until: snooze.date(from: Date())) } else { store.finish(todoID) }
                self.reschedule(todos: store.todos, customPriorities: store.customPriorities)
            }
            completionHandler()
            return
        }
        let kind = NotificationKind(rawValue: content.userInfo["kind"] as? String ?? "") ?? .dueSoon
        let title = content.userInfo["todoTitle"] as? String ?? content.body
        if UserDefaults.standard.object(forKey: "animatedNotificationPopup") as? Bool ?? true {
            DispatchQueue.main.async {
                NotificationPopupPresenter.shared.show(title: title, kind: kind)
            }
        }
        completionHandler()
    }
}

@MainActor private final class NotificationPopupPresenter {
    static let shared = NotificationPopupPresenter()
    private var panel: NSPanel?

    func show(title: String, kind: NotificationKind) {
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 360, height: 220), styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.center()
        self.panel?.close()
        panel.contentView = NSHostingView(rootView: NotificationPopupView(title: title, kind: kind) { panel.close() })
        self.panel = panel
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }
}

private struct NotificationPopupView: View {
    let title: String
    let kind: NotificationKind
    let close: () -> Void
    @State private var animate = false

    var body: some View {
        VStack(spacing: 14) {
            Text(kind.symbol)
                .font(.system(size: 54))
                .rotationEffect(.degrees(kind == .dueSoon ? (animate ? 7 : -7) : 0))
                .offset(y: kind == .overdue ? (animate ? 5 : -3) : 0)
            Text(kind.headline)
                .font(.title2.bold())
                .foregroundStyle(kind.tint)
            Text(title).multilineTextAlignment(.center)
            Button("Verstanden", action: close).buttonStyle(.borderedProminent).tint(kind.tint)
        }
        .padding(22)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(kind.tint.opacity(0.12))
        .onAppear { animate = true }
        .animation(.easeInOut(duration: 0.13).repeatCount(8, autoreverses: true), value: animate)
    }
}

private extension Int {
    func nonZero(or fallback: Int) -> Int { self == 0 ? fallback : self }
}
