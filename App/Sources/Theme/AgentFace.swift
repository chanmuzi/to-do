import SwiftUI

public enum AgentFaceState: String, CaseIterable, Sendable {
    case idle = "쉬는 중", listen = "듣는 중", think = "생각하는 중", read = "노트를 읽는 중"
    case write = "적는 중", search = "찾는 중", ask = "기다리는 중", done = "끝남", blocked = "막힘", dream = "기억 정리 중"
}

public enum AgentFaceSize: CaseIterable, Sendable {
    case small, regular, medium, large
    public var token: ComponentToken {
        switch self {
        case .small: .iconSmall
        case .regular: .iconMedium
        case .medium: .agentFaceMedium
        case .large: .agentFaceLarge
        }
    }
    var showsCorner: Bool { self == .medium || self == .large }
    var showsProps: Bool { self == .large }
}

/// 시안의 16 단위 벡터를 화면 크기에 맞게 그린다. 정지 상태에는 타임라인을 만들지 않는다.
public struct AgentFace: View {
    let theme: Theme
    let state: AgentFaceState
    let forceStill: Bool
    let size: AgentFaceSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(theme: Theme, state: AgentFaceState = .idle, size: AgentFaceSize = .regular, forceStill: Bool = false) {
        self.theme = theme
        self.state = state
        self.forceStill = forceStill
        self.size = size
    }

    public var body: some View {
        Group {
            if forceStill || reduceMotion || state == .done || state == .blocked {
                glyph(at: nil)
            } else {
                TimelineView(.animation) { glyph(at: $0.date.timeIntervalSinceReferenceDate) }
            }
        }
        .frame(width: theme.component(size.token), height: theme.component(size.token))
        .accessibilityLabel(state.rawValue)
    }

    package func glyph(at time: TimeInterval?) -> some View {
        let ink = theme.color(.text)
        let warn = theme.color(.warn)
        let periods = theme.tokens
        func phase(_ timing: AgentFaceTiming, delay: Double = 0, alternate: Bool = false) -> Double {
            let period = periods.period(timing)
            guard let time, period > 0 else { return 0 }
            let cycles = (time - delay) / period
            let t = cycles - floor(cycles)
            return alternate && Int(floor(cycles)).isMultiple(of: 2) == false ? 1 - t : t
        }
        func ease(_ t: Double) -> Double { (1 - cos(.pi * t)) / 2 }
        func pulse(_ t: Double) -> Double { time == nil ? 1 : 0.2 + 0.8 * ease(t < 0.4 ? t / 0.4 : (1 - t) / 0.6) }
        return Canvas { context, bounds in
            var base = context
            base.scaleBy(x: bounds.width / 16, y: bounds.height / 16)
            let stroke = size.showsProps ? 1.15 : 1.3
            func line(_ ctx: GraphicsContext, _ path: Path, _ width: Double, _ color: Color = ink) {
                ctx.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round))
            }
            func dot(_ ctx: GraphicsContext, _ x: Double, _ y: Double, _ r: Double, height: Double = 1, color: Color = ink) {
                ctx.fill(Path(ellipseIn: CGRect(x: x-r, y: y-r*height, width: 2*r, height: 2*r*height)), with: .color(color))
            }
            var head = base
            if size.showsCorner { head.translateBy(x: 0, y: 2.2); head.scaleBy(x: 0.84, y: 0.84) }
            if state == .listen {
                head.translateBy(x: 8, y: 12)
                head.rotate(by: .degrees(time == nil ? -10 : -11 + 4 * ease(phase(.nod) * 2)))
                head.translateBy(x: -8, y: -12)
            }
            line(head, Path(roundedRect: CGRect(x: 2.2, y: 2.8, width: 11.6, height: 10.4), cornerRadius: 3.2), stroke)
            switch state {
            case .done, .dream, .blocked:
                let y = state == .done ? 8.7 : state == .dream ? 7.9 : 8.3
                for x in [5.0, 8.8] {
                    var p = Path()
                    if state == .blocked {
                        p.move(to: CGPoint(x: x + 0.1, y: y)); p.addLine(to: CGPoint(x: x + 2.1, y: y))
                    } else {
                        p.move(to: CGPoint(x: x, y: y))
                        p.addQuadCurve(to: CGPoint(x: x + 2.2, y: y), control: CGPoint(x: x + 1.1, y: y + (state == .done ? -1.6 : 1.4)))
                    }
                    line(head, p, stroke)
                }
            default:
                var dx = state == .think ? 0.5 : 0
                if time != nil {
                    switch state {
                    case .read:
                        let t = phase(.scan)
                        dx = -1.3 + 2.6 * (t < 0.85 ? t / 0.85 : (1 - t) / 0.15)
                    case .write: dx = -0.9 + 1.8 * ease(phase(.write) * 2)
                    case .search: dx = -1.1 + 2.2 * ease(phase(.look) * 2)
                    default: break
                    }
                }
                let blink = max(0, 1 - abs(phase(.blink) - 0.95) / 0.05)
                for x in [6.1, 9.9] {
                    dot(head, x + dx, state == .think ? 7 : state == .write ? 9.3 : 8.2,
                        state == .listen ? 1.15 : 0.95, height: state == .idle ? 1 - 0.88 * blink : 1)
                }
            }
            var mark = base
            switch state {
            case .listen where size.showsCorner:
                for (index, data) in ["13.2 6.9 m 14.3 8.6 13.2 10.3 q", "14.9 5.6 m 16.8 8.6 14.9 11.6 q"].enumerated() {
                    mark.opacity = pulse(phase(.wave, delay: Double(index) * periods.period(.waveDelay)))
                    line(mark, Path(data)!, 1.1)
                }
            case .ask, .blocked, .done:
                guard size.showsCorner else { dot(base, 13.6, 2.9, 2, color: state == .done ? ink : warn); return }
                if state == .ask {
                    if time != nil { mark.translateBy(x: 0, y: 0.5 - 1.1 * ease(phase(.ask, alternate: true))) }
                    line(mark, Path("12.3 1.9 m 13.7 0.4 14.9 1.7 q 15.7 2.8 14 3.7 q 14 4.2 l 14 5.6 m 14 5.7 l")!, 1.3, warn)
                } else if state == .blocked {
                    line(mark, Path("13.8 0.6 m 13.8 3.7 l 13.8 5.5 m 13.8 5.6 l")!, 1.4, warn)
                } else { line(mark, Path("11.4 2.6 m 12.9 4.1 l 15.5 1.1 l")!, 1.3) }
            case .dream where size.showsCorner:
                if time != nil {
                    let t = phase(.dream)
                    mark.translateBy(x: -0.6 + t * 1.2, y: 1.2 - t * 2.4)
                    mark.opacity = t < 0.35 ? 0.35 + 0.65 * t / 0.35 : (1 - t) / 0.65
                }
                line(mark, Path("12.2 1 m 15 1 l 12.2 4.2 l 15 4.2 l")!, 1)
            case .think where size.showsProps:
                for i in 0..<3 {
                    mark.opacity = pulse(phase(.dots, delay: Double(i) * periods.period(.dotDelay)))
                    dot(mark, 10.4 + 2.4 * Double(i), 1.5, 0.8)
                }
            case .read where size.showsProps:
                line(mark, Path(roundedRect: CGRect(x: 12.3, y: 10.2, width: 3.4, height: 4.6), cornerRadius: 0.7), 1)
                line(mark, Path("13.3 11.8 m 14.7 11.8 l 13.3 13.2 m 14.7 13.2 l")!, 0.8)
            case .write where size.showsProps:
                if time != nil {
                    mark.translateBy(x: 16.1, y: 15.5)
                    mark.rotate(by: .degrees(-9 + 18 * ease(phase(.pencil, alternate: true))))
                    mark.translateBy(x: -16.1, y: -15.5)
                }
                line(mark, Path("15.4 9.6 m 12.5 14.2 l 12 15.5 l 13.2 14.7 l 16.1 10.1 l h")!, 1)
            case .search where size.showsProps:
                if time != nil {
                    let t = phase(.lens) * 4
                    let points = [(0.0,0.0),(-0.9,0.7),(0,1.2),(0.9,0.7),(0,0)]
                    let i = Int(t), f = t - floor(t)
                    mark.translateBy(x: points[i].0 * (1-f) + points[i+1].0 * f, y: points[i].1 * (1-f) + points[i+1].1 * f)
                }
                line(mark, Path(ellipseIn: CGRect(x: 11.9, y: 9.9, width: 3.4, height: 3.4)), 1.1)
                line(mark, Path("14.8 12.9 m 15.8 14.1 l")!, 1.1)
            default: break
            }
        }
    }
}
