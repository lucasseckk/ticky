import SwiftUI

// Shared Dynamic-Island look: deep black surfaces, capsules and a soft colored glow.

extension Animation {
    /// Short, springy, with a slight overshoot – like the Dynamic Island morphing.
    static let island = Animation.spring(response: 0.35, dampingFraction: 0.72)
}

extension View {
    /// Dark capsule surface used for pills, fields and bars.
    func islandCapsule() -> some View {
        background(Color.white.opacity(0.07), in: Capsule())
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.1), lineWidth: 1))
    }

    /// Calm dark card; an optional slim stripe on the left carries the priority color.
    func islandCard(stripe: Color? = nil, cornerRadius: CGFloat = 16) -> some View {
        padding(.leading, stripe == nil ? 0 : 6)
            .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: cornerRadius))
            .overlay(alignment: .leading) {
                if let stripe {
                    Capsule().fill(stripe).frame(width: 4).padding(.vertical, 10).padding(.leading, 6)
                }
            }
            .overlay(RoundedRectangle(cornerRadius: cornerRadius).strokeBorder(Color.white.opacity(0.08)))
    }

    /// Plain dark panel for settings and editor sections.
    func islandSurface(cornerRadius: CGFloat = 16) -> some View {
        background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: cornerRadius))
            .overlay(RoundedRectangle(cornerRadius: cornerRadius).strokeBorder(Color.white.opacity(0.1)))
    }
}

/// Small info pill on a card: date, repetition, group, reminder, link.
struct InfoPill: View {
    let text: String
    let systemImage: String
    var tint: Color = .white

    var body: some View {
        Label(text, systemImage: systemImage)
            .font(.caption2.weight(.medium))
            .lineLimit(1)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .foregroundStyle(tint == .white ? Color.white.opacity(0.75) : tint)
            .background(Color.white.opacity(0.08), in: Capsule())
    }
}

/// Round icon button as in the island header.
struct IslandIconButton: View {
    let systemImage: String
    var isOn = false
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .semibold))
                .frame(width: 30, height: 30)
                .foregroundStyle(isOn ? Color.black : Color.white)
                .background(isOn ? Color.white : Color.white.opacity(0.1), in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .help(label)
    }
}

/// Black pill switch whose highlight slides to the selected option.
struct IslandSwitch<Value: Hashable>: View {
    let options: [(value: Value, label: String, systemImage: String?)]
    @Binding var selection: Value
    @Namespace private var namespace

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.value) { option in
                let selected = option.value == selection
                Button { withAnimation(.island) { selection = option.value } } label: {
                    HStack(spacing: 5) {
                        if let image = option.systemImage { Image(systemName: image) }
                        Text(option.label).lineLimit(1)
                    }
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(selected ? Color.black : Color.white.opacity(0.7))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 7)
                    .background {
                        if selected { Capsule().fill(Color.white).matchedGeometryEffect(id: "highlight", in: namespace) }
                    }
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(3)
        .background(Color.black, in: Capsule())
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.12)))
    }
}
