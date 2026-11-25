import SwiftUI
import Theme

/// 확정 시안의 16단위 도형을 같은 칸, 같은 선 굵기로 그린다.
struct ScheduleGlyph: View {
    let symbol: String
    let theme: Theme

    var body: some View {
        Canvas { context, size in
            let scale = size.width / 16
            context.scaleBy(x: scale, y: scale)
            var path = Path()
            func line(_ points: CGPoint...) {
                guard let first = points.first else { return }
                path.move(to: first)
                for point in points.dropFirst() { path.addLine(to: point) }
            }
            switch symbol {
            case "clock":
                path.addEllipse(in: CGRect(x: 1.8, y: 1.8, width: 12.4, height: 12.4))
                line(.init(x: 8, y: 4.6), .init(x: 8, y: 8), .init(x: 10.2, y: 9.4))
            case "sun.max":
                path.addEllipse(in: CGRect(x: 5.3, y: 5.3, width: 5.4, height: 5.4))
                for index in 0..<8 {
                    let angle = Double(index) * .pi / 4
                    line(.init(x: 8 + 5.1*cos(angle), y: 8 + 5.1*sin(angle)),
                         .init(x: 8 + 6.5*cos(angle), y: 8 + 6.5*sin(angle)))
                }
            case "calendar":
                path.addRoundedRect(in: CGRect(x: 2.2, y: 3, width: 11.6, height: 10.8), cornerSize: .init(width: 1.6, height: 1.6))
                line(.init(x: 2.2, y: 6.3), .init(x: 13.8, y: 6.3))
                for x in [5.5, 10.5] { line(.init(x: x, y: 1.6), .init(x: x, y: 4)) }
            case "timer":
                path.addEllipse(in: CGRect(x: 2.7, y: 3.7, width: 10.6, height: 10.6))
                line(.init(x: 8, y: 9), .init(x: 8, y: 6.3))
                line(.init(x: 6.4, y: 1.8), .init(x: 9.6, y: 1.8))
            case "text.alignleft":
                for y in [4.4, 8, 11.6] { line(.init(x: 2.6, y: y), .init(x: y > 8 ? 9 : 13.4, y: y)) }
            case "chevron.left":
                line(.init(x: 10, y: 3), .init(x: 5, y: 8), .init(x: 10, y: 13))
            case "trash":
                line(.init(x: 3, y: 4.5), .init(x: 13, y: 4.5))
                line(.init(x: 6.3, y: 4.5), .init(x: 6.3, y: 3), .init(x: 9.7, y: 3), .init(x: 9.7, y: 4.5))
                line(.init(x: 4.4, y: 4.5), .init(x: 5.1, y: 13.5), .init(x: 10.9, y: 13.5), .init(x: 11.6, y: 4.5))
            default: break
            }
            context.stroke(path, with: .foreground, style: .init(lineWidth: theme.component(.iconStroke) / scale, lineCap: .round, lineJoin: .round))
        }.frame(width: theme.component(.menuIcon), height: theme.component(.menuIcon)).accessibilityHidden(true)
    }
}
