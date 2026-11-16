import CoreGraphics

/// 상단 줄 요소의 자리(spec 5.1, 5.2). 호버로 나타나는 것도 늘 자리를 차지하고,
/// 좁아지면 제목이 먼저 줄어든다(spec 16). 호버와 포커스는 입력이 아니다.
struct TopRowLayout: Hashable {
    struct Metrics: Hashable {
        var height: CGFloat
        var paddingLeading: CGFloat
        var paddingTrailing: CGFloat
        var gap: CGFloat
        var iconButton: CGFloat
    }

    struct Input: Hashable {
        var width: CGFloat
        /// 스페이스 표시의 너비. 없으면 자리도 없다.
        var spaceWidth: CGFloat?
        /// 제목이 다 보이는 너비.
        var titleWidth: CGFloat
        var reminderWidth: CGFloat?
        var showsProblem: Bool
    }

    var space: CGRect?
    var title: CGRect
    var search: CGRect
    var more: CGRect
    var add: CGRect
    var problem: CGRect?
    var reminder: CGRect?
    var pin: CGRect

    init(_ input: Input, metrics: Metrics) {
        let buttonY = ((metrics.height - metrics.iconButton) / 2).rounded()
        var trailing = input.width - metrics.paddingTrailing
        func takeTrailing(_ width: CGFloat) -> CGRect {
            let rect = CGRect(x: trailing - width, y: buttonY, width: width, height: metrics.iconButton)
            trailing = rect.minX - metrics.gap
            return rect
        }

        pin = takeTrailing(metrics.iconButton)
        reminder = input.reminderWidth.map(takeTrailing)
        problem = input.showsProblem ? takeTrailing(metrics.iconButton) : nil
        add = takeTrailing(metrics.iconButton)
        more = takeTrailing(metrics.iconButton)
        search = takeTrailing(metrics.iconButton)

        var leading = metrics.paddingLeading
        if let spaceWidth = input.spaceWidth {
            space = CGRect(x: leading, y: 0, width: spaceWidth, height: metrics.height)
            leading += spaceWidth + metrics.gap
        } else {
            space = nil
        }
        let available = max(0, trailing - leading)
        title = CGRect(x: leading, y: 0, width: min(input.titleWidth, available), height: metrics.height)
    }
}
