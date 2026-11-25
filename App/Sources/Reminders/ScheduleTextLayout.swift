import SwiftUI

/// 줄 기준선에서 대문자 높이의 절반을 올린 점을 이 칸의 가운데에 놓는다.
struct ScheduleTextLayout: Layout {
    let capHeight: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        subviews[0].sizeThatFits(proposal)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let size = ProposedViewSize(bounds.size)
        let baseline = subviews[0].dimensions(in: size)[.firstTextBaseline]
        subviews[0].place(at: CGPoint(x: bounds.minX, y: bounds.midY + capHeight / 2 - baseline),
                          anchor: .topLeading, proposal: size)
    }
}

#if DEBUG
/// 팝오버의 위쪽 끝에서 실제 표시 위치를 잰다. 캡처와 좌표 회귀 검사에서 함께 읽는다.
struct ScheduleCenterMeasurements: PreferenceKey {
    static let defaultValue: [String: CGFloat] = [:]
    static func reduce(value: inout [String: CGFloat], nextValue: () -> [String: CGFloat]) {
        value.merge(nextValue(), uniquingKeysWith: { _, last in last })
    }
}
#endif

extension View {
    @ViewBuilder func measureScheduleCenter(_ key: String, capHeight: CGFloat? = nil) -> some View {
        #if DEBUG
        overlay(alignment: Alignment(horizontal: .center, vertical: capHeight == nil ? .center : .firstTextBaseline)) {
            Color.clear.frame(width: 0, height: 0)
                .alignmentGuide(.firstTextBaseline) { _ in 0 }
                .background {
                    GeometryReader { geometry in
                        Color.clear.preference(key: ScheduleCenterMeasurements.self, value: [
                            key: geometry.frame(in: .named("schedule")).midY - (capHeight ?? 0) / 2
                        ])
                    }
                }.allowsHitTesting(false).accessibilityHidden(true)
        }
        #else
        self
        #endif
    }
}
