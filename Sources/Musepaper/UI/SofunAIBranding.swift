import SwiftUI

/// Native vector counterpart of assets/brand/sofunai-mark.svg.
/// The studio mark contains no product names and needs no network or image bundle.
struct SofunAIStudioMark: View {
    var body: some View {
        Canvas { context, size in
            var drawing = context
            drawing.scaleBy(x: size.width / 128, y: size.height / 128)

            drawing.fill(
                Path(roundedRect: CGRect(x: 8, y: 8, width: 112, height: 112), cornerRadius: 36),
                with: .color(Color(red: 246 / 255, green: 239 / 255, blue: 224 / 255))
            )

            var upper = Path()
            upper.move(to: CGPoint(x: 83, y: 29))
            upper.addLine(to: CGPoint(x: 57, y: 29))
            upper.addCurve(to: CGPoint(x: 29, y: 53), control1: CGPoint(x: 40, y: 29), control2: CGPoint(x: 29, y: 39))
            upper.addCurve(to: CGPoint(x: 57, y: 76), control1: CGPoint(x: 29, y: 67), control2: CGPoint(x: 40, y: 76))
            upper.addLine(to: CGPoint(x: 68, y: 76))
            drawing.stroke(upper, with: .color(Color(red: 224 / 255, green: 122 / 255, blue: 95 / 255)), style: StrokeStyle(lineWidth: 15, lineCap: .round))

            var lower = Path()
            lower.move(to: CGPoint(x: 45, y: 99))
            lower.addLine(to: CGPoint(x: 71, y: 99))
            lower.addCurve(to: CGPoint(x: 99, y: 75), control1: CGPoint(x: 88, y: 99), control2: CGPoint(x: 99, y: 89))
            lower.addCurve(to: CGPoint(x: 71, y: 52), control1: CGPoint(x: 99, y: 61), control2: CGPoint(x: 88, y: 52))
            lower.addLine(to: CGPoint(x: 60, y: 52))
            drawing.stroke(lower, with: .color(Color(red: 42 / 255, green: 122 / 255, blue: 106 / 255)), style: StrokeStyle(lineWidth: 15, lineCap: .round))

            drawing.fill(
                Path(ellipseIn: CGRect(x: 93, y: 20, width: 14, height: 14)),
                with: .color(Color(red: 126 / 255, green: 184 / 255, blue: 218 / 255))
            )
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityLabel("SofunAI Studio")
    }
}

struct SofunAIPublisherView: View {
    @Environment(\.locale) private var interfaceLocale
    var publisher = "SofunAI Studio"
    var summary: String?

    var body: some View {
        HStack(spacing: 12) {
            SofunAIStudioMark()
                .frame(width: 52, height: 52)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(publisher)
                    .font(.system(.headline, design: .rounded))
                Text(summary ?? L10n.tr("SofunAI 工作室出品并维护"))
                    .font(.caption)
                    .opacity(0.8)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
