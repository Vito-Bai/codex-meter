import SwiftUI

enum MeterTheme {
    static let canvas = adaptive(light: NSColor(calibratedWhite: 0.94, alpha: 1), dark: NSColor(calibratedRed: 0.025, green: 0.03, blue: 0.045, alpha: 1), name: "canvas")
    static let elevated = adaptive(light: NSColor(calibratedRed: 0.89, green: 0.91, blue: 0.94, alpha: 1), dark: NSColor(calibratedRed: 0.08, green: 0.095, blue: 0.125, alpha: 1), name: "elevated")
    static let line = adaptive(light: NSColor(calibratedWhite: 0.08, alpha: 0.14), dark: NSColor(calibratedWhite: 1, alpha: 0.13), name: "line")
    static let primaryText = adaptive(light: NSColor(calibratedWhite: 0.07, alpha: 0.92), dark: NSColor(calibratedWhite: 1, alpha: 0.96), name: "primaryText")
    static let secondaryText = adaptive(light: NSColor(calibratedWhite: 0.12, alpha: 0.58), dark: NSColor(calibratedWhite: 1, alpha: 0.6), name: "secondaryText")
    static let subtleFill = adaptive(light: NSColor(calibratedWhite: 0.08, alpha: 0.055), dark: NSColor(calibratedWhite: 1, alpha: 0.045), name: "subtleFill")
    static let controlFill = adaptive(light: NSColor(calibratedWhite: 0.08, alpha: 0.075), dark: NSColor(calibratedWhite: 1, alpha: 0.07), name: "controlFill")
    static let mint = adaptive(light: NSColor(calibratedRed: 0.04, green: 0.58, blue: 0.39, alpha: 1), dark: NSColor(calibratedRed: 0.34, green: 0.95, blue: 0.72, alpha: 1), name: "mint")
    static let yellow = adaptive(light: NSColor(calibratedRed: 0.72, green: 0.5, blue: 0.02, alpha: 1), dark: NSColor(calibratedRed: 0.98, green: 0.82, blue: 0.34, alpha: 1), name: "yellow")
    static let orange = adaptive(light: NSColor(calibratedRed: 0.84, green: 0.34, blue: 0.05, alpha: 1), dark: NSColor(calibratedRed: 1, green: 0.55, blue: 0.25, alpha: 1), name: "orange")
    static let red = adaptive(light: NSColor(calibratedRed: 0.8, green: 0.13, blue: 0.18, alpha: 1), dark: NSColor(calibratedRed: 1, green: 0.33, blue: 0.38, alpha: 1), name: "red")
    static let cyan = adaptive(light: NSColor(calibratedRed: 0.04, green: 0.46, blue: 0.72, alpha: 1), dark: NSColor(calibratedRed: 0.35, green: 0.78, blue: 1, alpha: 1), name: "cyan")
    static let violet = adaptive(light: NSColor(calibratedRed: 0.43, green: 0.27, blue: 0.82, alpha: 1), dark: NSColor(calibratedRed: 0.69, green: 0.52, blue: 1, alpha: 1), name: "violet")

    private static func adaptive(light: NSColor, dark: NSColor, name: String) -> Color {
        Color(nsColor: NSColor(name: NSColor.Name("CodexMeter.\(name)")) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
        })
    }

    static func quotaColor(remaining: Int, available: Bool = true) -> Color {
        guard available else { return .gray }
        switch remaining {
        case 81...: return mint
        case 50...80: return yellow
        case 25...49: return orange
        default: return red
        }
    }
}

struct LiquidGlassBackground: View {
    var accent: Color = MeterTheme.cyan
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Group {
            if #available(macOS 26.0, *) {
                // Keep the host window optically open. Individual content surfaces
                // apply Liquid Glass directly and can therefore sample the actual
                // desktop instead of an already-flattened full-window glass layer.
                Rectangle()
                    .fill(.clear)
            } else {
                ZStack {
                Rectangle().fill(.ultraThinMaterial)
                    Rectangle().fill(
                        colorScheme == .dark
                            ? Color.black.opacity(0.12)
                            : Color.white.opacity(0.025)
                    )
                    LinearGradient(
                        colors: backgroundColors,
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    RadialGradient(
                        colors: [accent.opacity(colorScheme == .dark ? 0.12 : 0.055), .clear],
                        center: .topTrailing,
                        startRadius: 0,
                        endRadius: 300
                    )
                    LinearGradient(
                        colors: colorScheme == .dark
                            ? [.white.opacity(0.075), .clear, .white.opacity(0.018)]
                            : [.white.opacity(0.18), .clear, .white.opacity(0.045)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .blendMode(.screen)
                }
            }
        }
        .ignoresSafeArea()
    }

    private var backgroundColors: [Color] {
        if colorScheme == .dark {
            return [
                Color(red: 0.08, green: 0.1, blue: 0.14).opacity(0.22),
                Color.black.opacity(0.18),
                Color(red: 0.04, green: 0.09, blue: 0.13).opacity(0.16)
            ]
        }
        return [
            Color(red: 0.98, green: 0.985, blue: 1).opacity(0.13),
            Color(red: 0.83, green: 0.89, blue: 0.96).opacity(0.08),
            Color.white.opacity(0.055)
        ]
    }
}

struct GlassCard<Content: View>: View {
    let content: Content
    @Environment(\.colorScheme) private var colorScheme

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        if #available(macOS 26.0, *) {
            content
                .padding(16)
                .glassEffect(
                    .clear,
                    in: RoundedRectangle(cornerRadius: 18, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                colors: cardBorderColors,
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 0.65
                        )
                }
        } else {
            content
                .padding(16)
                .background(
                ZStack {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(.thinMaterial)
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: cardFillColors,
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                colors: cardBorderColors,
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 0.7
                        )
                    RoundedRectangle(cornerRadius: 17.3, style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                colors: [
                                    .white.opacity(colorScheme == .dark ? 0.13 : 0.52),
                                    .clear,
                                    .white.opacity(colorScheme == .dark ? 0.025 : 0.12)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            lineWidth: 0.45
                        )
                        .padding(0.7)
                }
                .shadow(color: .black.opacity(colorScheme == .dark ? 0.26 : 0.12), radius: 14, y: 7)
                .shadow(color: .white.opacity(colorScheme == .dark ? 0.07 : 0.3), radius: 1, y: -1)
            )
        }
    }

    private var cardFillColors: [Color] {
        colorScheme == .dark
            ? [.white.opacity(0.105), MeterTheme.elevated.opacity(0.2), .black.opacity(0.1)]
            : [.white.opacity(0.58), MeterTheme.elevated.opacity(0.28), .white.opacity(0.38)]
    }

    private var cardBorderColors: [Color] {
        colorScheme == .dark
            ? [.white.opacity(0.32), .white.opacity(0.065), .white.opacity(0.14)]
            : [.white.opacity(0.86), .black.opacity(0.1), .white.opacity(0.58)]
    }
}

struct InsetGlassSurface: View {
    var cornerRadius: CGFloat = 12
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        if #available(macOS 26.0, *) {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(MeterTheme.subtleFill)
                .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(MeterTheme.line.opacity(0.72), lineWidth: 0.65)
                }
        } else {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(.ultraThinMaterial)
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: colorScheme == .dark
                                ? [.white.opacity(0.09), .white.opacity(0.025), .black.opacity(0.08)]
                                : [.white.opacity(0.52), .white.opacity(0.18), .white.opacity(0.3)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: colorScheme == .dark
                                ? [.white.opacity(0.25), .white.opacity(0.06), .white.opacity(0.12)]
                                : [.white.opacity(0.82), .black.opacity(0.08), .white.opacity(0.54)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 0.7
                    )
            }
            .shadow(color: .black.opacity(colorScheme == .dark ? 0.15 : 0.07), radius: 5, y: 2)
        }
    }
}

struct ClearGlassCapsuleModifier: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content.glassEffect(.clear, in: Capsule())
        } else {
            content.background(Capsule().fill(.ultraThinMaterial))
        }
    }
}

struct ClearGlassRoundedModifier: ViewModifier {
    let cornerRadius: CGFloat

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content.glassEffect(
                .clear,
                in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            )
        } else {
            content.background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(.ultraThinMaterial)
            )
        }
    }
}

struct ClearGlassCircleModifier: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content.glassEffect(.clear, in: Circle())
        } else {
            content.background(Circle().fill(.ultraThinMaterial))
        }
    }
}

struct SectionEyebrow: View {
    let text: String

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 10, weight: .medium, design: .rounded))
            .tracking(0.8)
            .foregroundStyle(MeterTheme.secondaryText)
    }
}

struct StatusPill: View {
    let text: String
    let color: Color

    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 6, height: 6)
                .shadow(color: color.opacity(0.8), radius: 4)
            Text(text)
                .font(.system(size: 11, weight: .medium, design: .rounded))
        }
        .foregroundStyle(MeterTheme.primaryText)
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .modifier(ClearGlassCapsuleModifier())
        .overlay(Capsule().strokeBorder(MeterTheme.line.opacity(0.7), lineWidth: 0.6))
    }
}

struct GlassIconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(width: 30, height: 30)
            .modifier(InteractiveCircleGlassModifier(isPressed: configuration.isPressed))
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .opacity(configuration.isPressed ? 0.78 : 1)
            .animation(.spring(duration: 0.22, bounce: 0.25), value: configuration.isPressed)
    }
}

struct GlassActionButtonStyle: ButtonStyle {
    var prominent = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .foregroundStyle(prominent ? Color.black.opacity(0.82) : MeterTheme.primaryText)
            .modifier(InteractiveCapsuleGlassModifier(
                isPressed: configuration.isPressed,
                prominent: prominent
            ))
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(duration: 0.2, bounce: 0.2), value: configuration.isPressed)
    }
}

struct CompactGlassButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 9.5, weight: .semibold, design: .rounded))
            .foregroundStyle(MeterTheme.secondaryText)
            .frame(width: 82, height: 28)
            .contentShape(Capsule())
            .modifier(InteractiveCapsuleGlassModifier(isPressed: configuration.isPressed))
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.spring(duration: 0.2, bounce: 0.18), value: configuration.isPressed)
    }
}

private struct InteractiveCircleGlassModifier: ViewModifier {
    let isPressed: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content.glassEffect(.regular.interactive(), in: Circle())
        } else {
            content.background(
                Circle()
                    .fill(.thinMaterial)
                    .overlay(Circle().fill(MeterTheme.controlFill.opacity(isPressed ? 0.8 : 0.3)))
                    .overlay(Circle().strokeBorder(.white.opacity(isPressed ? 0.3 : 0.18), lineWidth: 0.7))
                    .shadow(color: .black.opacity(0.12), radius: 4, y: 2)
            )
        }
    }
}

private struct InteractiveCapsuleGlassModifier: ViewModifier {
    let isPressed: Bool
    var prominent = false

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            if prominent {
                content.glassEffect(.regular.tint(MeterTheme.mint).interactive(), in: Capsule())
            } else {
                content.glassEffect(.regular.interactive(), in: Capsule())
            }
        } else {
            content.background(
                ZStack {
                    Capsule().fill(.thinMaterial)
                    Capsule().fill(
                        prominent
                            ? MeterTheme.mint.opacity(isPressed ? 0.72 : 0.92)
                            : MeterTheme.controlFill.opacity(isPressed ? 0.9 : 0.3)
                    )
                }
                .overlay(Capsule().strokeBorder(.white.opacity(prominent ? 0.2 : (isPressed ? 0.28 : 0.16)), lineWidth: 0.7))
                .shadow(color: .black.opacity(0.1), radius: 4, y: 2)
            )
        }
    }
}

struct InteractiveRoundedGlassModifier: ViewModifier {
    let cornerRadius: CGFloat
    var selected = false

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content.glassEffect(
                .clear.interactive(),
                in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            )
        } else {
            content.background(InsetGlassSurface(cornerRadius: cornerRadius))
        }
    }
}
