import SwiftUI

struct GlassPanelModifier: ViewModifier {
    let cornerRadius: CGFloat
    let tintOpacity: Double

    func body(content: Content) -> some View {
        content
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(.ultraThinMaterial)
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    .white.opacity(0.06),
                                    Color.black.opacity(0.40),
                                    Color(red: 0.18, green: 0.22, blue: 0.34).opacity(tintOpacity)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(.white.opacity(0.18), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.14), radius: 10, x: 0, y: 2)
    }
}

extension View {
    func glassPanel(cornerRadius: CGFloat = 28, tintOpacity: Double = 0.10) -> some View {
        modifier(GlassPanelModifier(cornerRadius: cornerRadius, tintOpacity: tintOpacity))
    }

    func glassInputShell() -> some View {
        self
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.white.opacity(0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(.white.opacity(0.22), lineWidth: 1)
            )
    }

    func glassChip(selected: Bool = false) -> some View {
        self
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(.thinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(selected ? Color.white.opacity(0.08) : Color.black.opacity(0.12))
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(.white.opacity(selected ? 0.22 : 0.14), lineWidth: 1)
            )
    }
}

struct DashboardActionButtonStyle: ButtonStyle {
    var prominent = false
    var destructive = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .padding(.horizontal, 16)
            .padding(.vertical, 9)
            .background(
                Capsule(style: .continuous)
                    .fill(backgroundColor(pressed: configuration.isPressed))
            )
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(.white.opacity(0.22), lineWidth: 1)
            )
            .foregroundStyle(foregroundColor)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.14), value: configuration.isPressed)
    }

    private var foregroundColor: Color {
        if prominent {
            return .white
        }
        if destructive {
            return Color(red: 0.66, green: 0.18, blue: 0.26)
        }
        return .primary
    }

    private func backgroundColor(pressed: Bool) -> Color {
        if prominent {
            return pressed
                ? Color(red: 0.24, green: 0.44, blue: 0.60)
                : Color(red: 0.31, green: 0.53, blue: 0.69)
        }

        if destructive {
            return pressed
                ? Color.white.opacity(0.36)
                : Color.white.opacity(0.28)
        }

        return pressed
            ? Color.white.opacity(0.34)
            : Color.white.opacity(0.24)
    }
}

struct StatusPill: View {
    let text: String
    var tint: Color = .white

    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .medium))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule(style: .continuous)
                    .fill(tint.opacity(0.16))
            )
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(.white.opacity(0.18), lineWidth: 1)
            )
    }
}

struct ProviderAvatar: View {
    let name: String

    private var initials: String {
        let parts = name.split(separator: " ")
        let letters = parts.prefix(2).compactMap { $0.first }
        if !letters.isEmpty {
            return String(letters)
        }
        return String(name.prefix(2))
    }

    private var gradient: LinearGradient {
        let palette: [(Color, Color)] = [
            (.green, .mint),
            (.cyan, .blue),
            (.pink, .orange),
            (.teal, .cyan),
            (.indigo, .purple)
        ]
        let pair = palette[abs(name.hashValue) % palette.count]
        return LinearGradient(colors: [pair.0, pair.1], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    var body: some View {
        Circle()
            .fill(gradient)
            .frame(width: 40, height: 40)
            .overlay(
                Text(initials.uppercased())
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
            )
    }
}

struct GlassField<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)

            content
        }
    }
}

struct MetadataLine: View {
    let title: String
    let value: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 92, alignment: .leading)

            Text(value)
                .font(.system(size: 13))
                .textSelection(.enabled)

            Spacer(minLength: 0)
        }
    }
}

struct SectionCard<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title)
                .font(.system(size: 14, weight: .semibold))
            content
        }
        .padding(18)
        .glassPanel(cornerRadius: 24, tintOpacity: 0.06)
    }
}
