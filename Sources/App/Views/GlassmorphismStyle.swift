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

