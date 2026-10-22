import SwiftUI

// MARK: - Progress ring

struct RingView<Content: View>: View {
    var progress: Double
    var tint: Color
    var lineWidth: CGFloat = 10
    var trackOpacity: Double = 0.18
    @ViewBuilder var content: () -> Content

    var body: some View {
        ZStack {
            Circle()
                .stroke(tint.opacity(trackOpacity), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: min(1, max(0.0001, progress)))
                .stroke(
                    AngularGradient(
                        colors: [tint.opacity(0.55), tint],
                        center: .center,
                        startAngle: .degrees(-90),
                        endAngle: .degrees(270)
                    ),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
            content()
        }
    }
}
