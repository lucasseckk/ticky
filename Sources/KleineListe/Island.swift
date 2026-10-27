import SwiftUI

// Shared Dynamic-Island look: deep black surfaces, capsules and a soft colored glow.

extension Animation {
    /// Short, springy, with a slight overshoot – like the Dynamic Island morphing.
    static let island = Animation.spring(response: 0.35, dampingFraction: 0.72)
}

extension View {
    /// Dark capsule surface used for pills, fields and bars.
    func islandCapsule(tint: Color = .white, active: Bool = false) -> some View {
        background(active ? tint.opacity(0.28) : Color.white.opacity(0.07), in: Capsule())
            .overlay(Capsule().strokeBorder(active ? tint.opacity(0.7) : Color.white.opacity(0.1), lineWidth: 1))
    }

    /// Black card that fades from the tint color on the left, with a glowing, slowly shimmering border.
    func islandCard(tint: Color, cornerRadius: CGFloat = 18, shimmer: Bool = true) -> some View {
        modifier(IslandCard(tint: tint, cornerRadius: cornerRadius, shimmer: shimmer))
    }

    /// Plain dark panel for settings and editor sections.
    func islandSurface(cornerRadius: CGFloat = 16) -> some View {
        background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: cornerRadius))
            .overlay(RoundedRectangle(cornerRadius: cornerRadius).strokeBorder(Color.white.opacity(0.1)))
    }
}

private struct IslandCard: ViewModifier {
    let tint: Color
    let cornerRadius: CGFloat
    let shimmer: Bool
    @State private var phase: CGFloat = -1

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius)
        content
            .background(
                LinearGradient(stops: [.init(color: tint.opacity(0.75), location: 0), .init(color: tint.opacity(0.22), location: 0.35), .init(color: .black, location: 0.8)],
                               startPoint: .leading, endPoint: .trailing),
                in: shape
            )
            .overlay(shape.strokeBorder(LinearGradient(colors: [tint.opacity(0.9), tint.opacity(0.15)], startPoint: .leading, endPoint: .trailing), lineWidth: 1.2))
            .overlay {
                if shimmer {
                    // A highlight band travels along the border.
                    GeometryReader { proxy in
                        LinearGradient(colors: [.clear, tint.opacity(0.95), .white.opacity(0.8), tint.opacity(0.95), .clear], startPoint: .leading, endPoint: .trailing)
                            .frame(width: proxy.size.width * 0.35)
                            .offset(x: phase * proxy.size.width)
                    }
                    .mask(shape.strokeBorder(lineWidth: 1.6))
                    .allowsHitTesting(false)
                    .onAppear {
                        withAnimation(.linear(duration: 4.5).repeatForever(autoreverses: false)) { phase = 1.2 }
                    }
                }
            }
            .shadow(color: tint.opacity(0.35), radius: 8)
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
            .foregroundStyle(tint == .white ? Color.white.opacity(0.85) : tint)
            .background(tint.opacity(tint == .white ? 0.1 : 0.2), in: Capsule())
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
