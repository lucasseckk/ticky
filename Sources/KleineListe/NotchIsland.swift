import AppKit
import SwiftUI

/// Optional pill hanging from the notch (#50); on Macs without a notch it sits below the menu bar.
/// The window always has the pill's size, so it never blocks clicks next to it.
@MainActor enum NotchIsland {
    static var store: Store?
    static var dev: DevStore?
    private static var panel: NSPanel?
    private static var screenObserver: NSObjectProtocol?
    private static let collapsed = CGSize(width: 220, height: 30)
    private static let expanded = CGSize(width: 340, height: 76)

    static func setEnabled(_ enabled: Bool) {
        panel?.orderOut(nil)
        panel = nil
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
        screenObserver = nil
        guard enabled, let store, let dev else { return }
        let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        panel.contentView = NSHostingView(rootView: IslandPill(store: store, dev: dev, notchHeight: notchHeight, onHover: resize))
        self.panel = panel
        resize(expanded: false)
        panel.orderFrontRegardless()
        // Displays plugged in or out: rebuild for the new geometry.
        screenObserver = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { setEnabled(true) }
        }
    }

    /// Prefers the built-in display with a notch, otherwise the main display.
    private static var screen: NSScreen? { NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.main }
    private static var notchHeight: CGFloat { screen?.safeAreaInsets.top ?? 0 }

    private static func resize(expanded: Bool) {
        guard let panel, let screen else { return }
        let size = expanded ? Self.expanded : collapsed
        let height = size.height + notchHeight
        let top = notchHeight > 0 ? screen.frame.maxY : screen.visibleFrame.maxY - 6
        panel.setFrame(NSRect(x: screen.frame.midX - size.width / 2, y: top - height, width: size.width, height: height), display: true)
    }
}

struct IslandPill: View {
    @ObservedObject var store: Store
    @ObservedObject var dev: DevStore
    let notchHeight: CGFloat
    let onHover: (Bool) -> Void
    @State private var expanded = false

    var body: some View {
        let reviews = dev.pullRequests(in: .review).count
        let next = store.openTodos.filter { $0.due != nil }.min { $0.due! < $1.due! }
        VStack(spacing: 4) {
            HStack(spacing: 6) {
                Circle()
                    .fill(store.overdueCount > 0 ? Color.red : store.count == 0 ? Color.green : Color.white)
                    .frame(width: 6, height: 6)
                    .shadow(color: store.overdueCount > 0 ? .red : .clear, radius: 3)
                Text(summary(reviews: reviews)).lineLimit(1)
            }
            .font(.system(size: 12, weight: .semibold))
            if expanded {
                if let next, let due = next.due {
                    Text("Als Nächstes: \(next.title) · \(due.formatted(.relative(presentation: .named)))")
                        .lineLimit(1)
                        .foregroundStyle(due < Date() ? Color.red : Color.secondary)
                } else {
                    Text("Nichts fällig").foregroundStyle(.secondary)
                }
                Text("Klicken zum Öffnen").font(.caption2).foregroundStyle(.tertiary)
            }
        }
        .font(.caption)
        .padding(.horizontal, 14)
        .padding(.top, notchHeight > 0 ? notchHeight : 0)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black, in: UnevenRoundedRectangle(
            topLeadingRadius: notchHeight > 0 ? 0 : 15, bottomLeadingRadius: 15,
            bottomTrailingRadius: 15, topTrailingRadius: notchHeight > 0 ? 0 : 15))
        .contentShape(Rectangle())
        .onHover { hovering in
            onHover(hovering)
            withAnimation(.island) { expanded = hovering }
        }
        .onTapGesture { GlobalShortcut.openPanel() }
        .environment(\.colorScheme, .dark)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }

    private func summary(reviews: Int) -> String {
        var parts = [store.count == 0 ? "Alles erledigt" : "\(store.count) offen"]
        if expanded && store.overdueCount > 0 { parts.append("\(store.overdueCount) überfällig") }
        if reviews > 0 { parts.append(reviews == 1 ? "1 PR wartet" : "\(reviews) PRs warten") }
        return parts.joined(separator: " · ")
    }
}
