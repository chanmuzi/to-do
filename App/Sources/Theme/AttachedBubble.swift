import SwiftUI

/// 일정 상세와 컨텍스트 목록의 꼬리, 윤곽선과 그림자.
package struct AttachedBubble: View {
    package enum Edge { case leading, top, bottom }
    let theme: Theme
    let edge: Edge
    let tip: CGFloat
    let radius: CGFloat
    let outline: Color

    package init(theme: Theme, edge: Edge, tip: CGFloat, radius: CGFloat, outline: Color? = nil) {
        self.theme = theme
        self.edge = edge
        self.tip = tip
        self.radius = radius
        self.outline = outline ?? theme.color(.line)
    }

    package var body: some View {
        GeometryReader { geometry in
            let rect = CGRect(origin: .zero, size: geometry.size)
            let shape = path(in: rect)
            let shadow = theme.shadow(.pop).last
            shape.fill(theme.color(.surface))
                .shadow(color: shadow?.color.color ?? .clear, radius: (shadow?.blur ?? 0) / 2, y: shadow?.y ?? 0)
                .overlay { shape.stroke(outline, lineWidth: theme.shape(.borderWidth)) }
        }
    }

    private func path(in rect: CGRect) -> Path {
        let tail = theme.component(.chromePaddingEnd)
        let length = edge == .leading ? rect.height : rect.width
        let center = min(max(tip, radius + tail), length - radius - tail)
        func point(_ along: CGFloat, _ outward: CGFloat) -> CGPoint {
            switch edge {
            case .leading: CGPoint(x: -outward, y: along)
            case .top: CGPoint(x: along, y: -outward)
            case .bottom: CGPoint(x: along, y: rect.height + outward)
            }
        }
        var triangle = Path()
        triangle.move(to: point(center - tail, 0))
        triangle.addLine(to: point(center, tail))
        triangle.addLine(to: point(center + tail, 0))
        triangle.closeSubpath()
        return Path(roundedRect: rect, cornerRadius: radius).union(triangle)
    }
}
