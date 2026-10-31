import Foundation

/// Which reminders get scheduled and what the user is told about it (#129).
struct ReminderPlan: Equatable, Sendable {
    /// macOS keeps at most 64 pending notifications per app; a few stay free for snooze and test.
    static let limit = 60

    var planned = 0
    var skipped = 0
    var failures: [String] = []

    /// The soonest `limit` items; the rest is counted as skipped. Items without a date come last.
    static func soonest<Item>(_ items: [(item: Item, date: Date?)], limit: Int = limit) -> (chosen: [Item], skipped: Int) {
        let sorted = items.sorted { ($0.date ?? .distantFuture) < ($1.date ?? .distantFuture) }
        return (sorted.prefix(limit).map(\.item), max(sorted.count - limit, 0))
    }

    /// Shown in red in the panel: reminders that silently would not arrive.
    var problem: String? {
        guard let first = failures.first else { return nil }
        return String(localized: "\(failures.count) von \(planned + failures.count) Erinnerungen konnten nicht geplant werden: \(first)")
    }

    /// Shown in the settings, so it stays clear what is actually scheduled.
    var summary: String? {
        guard planned + failures.count + skipped > 0 else { return nil }
        if skipped > 0 { return String(localized: "\(planned) Erinnerungen geplant, die nächsten zuerst. \(skipped) spätere werden beim Öffnen von Ticky nachgeplant.") }
        return String(localized: "\(planned) Erinnerungen geplant.")
    }
}
