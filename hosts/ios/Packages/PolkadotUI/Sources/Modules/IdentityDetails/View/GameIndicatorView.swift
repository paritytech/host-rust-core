import SwiftUI

private struct EqualSegmentCircle: Shape {
    var segments: Int = 8

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2

        let slotAngle = 360.0 / Double(segments) // 45 degrees per slot
        let drawAngle = slotAngle / 2.0 // 22.5 degrees (exactly half for equal gap)
        let halfDraw = drawAngle / 4.0

        for i in 0 ..< segments {
            // Center angle for this segment (0, 45, 90, etc.)
            // -90.0 shifts the starting point to 12 o'clock
            let centerAngle = Double(i) * slotAngle - 90.0

            let startAngle = Angle(degrees: centerAngle - halfDraw)
            let endAngle = Angle(degrees: centerAngle + halfDraw)

            // Calculate exact start point to prevent SwiftUI from drawing connecting lines
            let startX = center.x + radius * CGFloat(cos(startAngle.radians))
            let startY = center.y + radius * CGFloat(sin(startAngle.radians))

            path.move(to: CGPoint(x: startX, y: startY))

            path.addArc(
                center: center,
                radius: radius,
                startAngle: startAngle,
                endAngle: endAngle,
                clockwise: false
            )
        }

        return path
    }
}

struct GameIndicatorView: View {
    var filled: Bool = false
    private let color = Color(hex: 0x9BA0A4)

    var body: some View {
        ZStack {
            if filled {
                Circle().fill(color)
            }
            EqualSegmentCircle(segments: 8)
                .stroke(
                    color,
                    style: StrokeStyle(lineWidth: 2, lineCap: .square)
                )
        }
        .frame(width: 14, height: 14)
        .compositingGroup()
    }
}

#Preview(traits: .fixedLayout(width: 100, height: 100)) {
    GameIndicatorView()
}
