import SwiftUI

enum MuseTheme {
    static let canvas = Color(red: 0.028, green: 0.030, blue: 0.034)
    static let sidebar = Color(red: 0.040, green: 0.042, blue: 0.046)
    static let panel = Color.white.opacity(0.045)
    static let panelStrong = Color.white.opacity(0.07)
    static let field = Color.white.opacity(0.04)
    static let border = Color.white.opacity(0.09)
    static let borderStrong = Color.white.opacity(0.14)
    static let ink = Color(red: 0.95, green: 0.935, blue: 0.90)
    static let muted = Color.white.opacity(0.42)
    static let amber = Color(red: 0.93, green: 0.55, blue: 0.20)
    static let amberSoft = Color(red: 0.58, green: 0.25, blue: 0.08)
    static let moss = Color(red: 0.36, green: 0.68, blue: 0.49)
}

enum MuseHit {
    static let tab: CGFloat = 36
    static let chip: CGFloat = 34
    static let primary: CGFloat = 48
    static let tagFont: CGFloat = 12
}

struct MuseBackdrop: View {
    var body: some View {
        ZStack {
            MuseTheme.canvas
            RadialGradient(
                colors: [MuseTheme.amber.opacity(0.07), .clear],
                center: UnitPoint(x: 0.88, y: 0.0),
                startRadius: 0,
                endRadius: 480
            )
            LinearGradient(
                colors: [.clear, Color.black.opacity(0.28)],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .ignoresSafeArea()
    }
}

struct WallpaperPlaceholder: View {
    var body: some View {
        GeometryReader { proxy in
            ZStack {
                LinearGradient(
                    colors: [
                        Color(red: 0.045, green: 0.07, blue: 0.09),
                        Color(red: 0.05, green: 0.13, blue: 0.14),
                        Color(red: 0.28, green: 0.14, blue: 0.08)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                Circle()
                    .fill(RadialGradient(colors: [Color.orange.opacity(0.38), .clear], center: .center, startRadius: 0, endRadius: 160))
                    .frame(width: proxy.size.width * 0.52)
                    .offset(x: proxy.size.width * 0.30, y: -proxy.size.height * 0.22)
                    .blur(radius: 18)
                Path { path in
                    path.move(to: CGPoint(x: 0, y: proxy.size.height * 0.78))
                    path.addCurve(
                        to: CGPoint(x: proxy.size.width, y: proxy.size.height * 0.55),
                        control1: CGPoint(x: proxy.size.width * 0.28, y: proxy.size.height * 0.62),
                        control2: CGPoint(x: proxy.size.width * 0.68, y: proxy.size.height * 0.82)
                    )
                    path.addLine(to: CGPoint(x: proxy.size.width, y: proxy.size.height))
                    path.addLine(to: CGPoint(x: 0, y: proxy.size.height))
                    path.closeSubpath()
                }
                .fill(Color.black.opacity(0.38))
            }
        }
    }
}

private struct MusePanelModifier: ViewModifier {
    let radius: CGFloat
    let strong: Bool

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(strong ? MuseTheme.panelStrong : MuseTheme.panel)
            )
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(strong ? MuseTheme.borderStrong : MuseTheme.border, lineWidth: 1)
            )
    }
}

private struct MuseFieldModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(MuseTheme.field)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(MuseTheme.border, lineWidth: 1)
            )
    }
}

private struct MuseHitMinHeightModifier: ViewModifier {
    let height: CGFloat

    func body(content: Content) -> some View {
        content.frame(minHeight: height)
    }
}

struct MusePrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .frame(maxWidth: .infinity)
            .frame(minHeight: MuseHit.primary)
            .padding(.horizontal, 14)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(MuseTheme.amber.opacity(configuration.isPressed ? 0.78 : 0.95))
            )
            .foregroundStyle(.black)
            .opacity(configuration.isPressed ? 0.9 : 1)
    }
}

/// Soft control cluster background for pickers / steppers in the workbench.
struct MuseControlCluster<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        HStack(spacing: 10) {
            content()
        }
        .padding(.horizontal, 10)
        .museHitMinHeight(MuseHit.chip)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(0.035))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(MuseTheme.border, lineWidth: 1)
        )
    }
}

extension View {
    func musePanel(radius: CGFloat = 16, strong: Bool = false) -> some View {
        modifier(MusePanelModifier(radius: radius, strong: strong))
    }

    func museField() -> some View {
        modifier(MuseFieldModifier())
    }

    func museHitMinHeight(_ height: CGFloat = MuseHit.primary) -> some View {
        modifier(MuseHitMinHeightModifier(height: height))
    }
}
