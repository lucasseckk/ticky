import SwiftUI

enum PanelSection: String, CaseIterable, Identifiable {
    case todos, dev
    var id: String { rawValue }
    var label: String {
        switch self {
        case .todos: return "To-Dos"
        case .dev: return "Dev"
        }
    }
    var systemImage: String {
        switch self {
        case .todos: return "checklist"
        case .dev: return "chevron.left.forwardslash.chevron.right"
        }
    }
}

/// Dev section: pull requests, urgent issues and agent issues from GitHub (see #22).
struct DevView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "chevron.left.forwardslash.chevron.right").font(.system(size: 34))
            Text("GitHub ist noch nicht verbunden").font(.headline)
            Text("Hier erscheinen bald Pull Requests, dringende Issues und Agent-Issues aus deinen Repositories.")
                .font(.callout)
                .multilineTextAlignment(.center)
        }
        .foregroundStyle(.secondary)
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
