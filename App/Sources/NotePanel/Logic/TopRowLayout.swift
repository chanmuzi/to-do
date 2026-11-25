import CoreGraphics

/// 상단 조작은 오른쪽부터 배치하고 남은 너비를 제목에 쓴다.
struct TopRowLayout: Hashable {
    struct Metrics: Hashable {
        var height: CGFloat
        var paddingLeading: CGFloat
        var paddingTrailing: CGFloat
        var gap: CGFloat
        var iconButton: CGFloat
        var dividerWidth: CGFloat = 1
        /// 호버 바탕 사이의 간격. 누름은 이웃한 두 조작이 절반씩 받는다.
        var buttonGap: CGFloat = 0
    }

    struct Input: Hashable {
        var width: CGFloat
        /// 제목이 다 보이는 너비.
        var titleWidth: CGFloat
        var hasSchedules: Bool
        var showsControls = true
        var allowsAgent = true
        var hasAgentActivity = false
        var isPinned = false
        var showsProblem: Bool
    }

    var title: CGRect
    var more: CGRect
    var problem: CGRect?
    var close: CGRect = .zero
    var divider: CGRect = .zero
    var agent: CGRect = .zero
    var clock: CGRect = .zero
    var pin: CGRect

    init(_ input: Input, metrics: Metrics) {
        let buttonY = (metrics.height - metrics.iconButton) / 2
        var trailing = input.width - metrics.paddingTrailing
        func takeTrailing(_ width: CGFloat, gap: CGFloat) -> CGRect {
            trailing -= gap
            let rect = CGRect(x: trailing - width, y: buttonY, width: width, height: metrics.iconButton)
            trailing = rect.minX
            return rect
        }

        close = input.showsControls ? takeTrailing(metrics.iconButton, gap: 0) : .zero
        divider = input.showsControls ? takeTrailing(metrics.dividerWidth, gap: metrics.gap) : .zero
        more = input.showsControls ? takeTrailing(metrics.iconButton, gap: metrics.gap) : .zero
        let showsPin = input.showsControls || input.isPinned
        pin = showsPin ? takeTrailing(metrics.iconButton, gap: input.showsControls ? metrics.buttonGap : 0) : .zero
        if input.hasSchedules {
            clock = takeTrailing(metrics.iconButton, gap: showsPin ? metrics.buttonGap : 0)
        }
        let showsAgent = input.allowsAgent && (input.showsControls || input.hasAgentActivity)
        if showsAgent {
            agent = takeTrailing(metrics.iconButton, gap: metrics.buttonGap)
        }
        problem = input.showsProblem ? takeTrailing(metrics.iconButton, gap: metrics.buttonGap) : nil
        trailing -= metrics.gap

        let leading = metrics.paddingLeading
        let available = max(0, trailing - leading)
        title = CGRect(x: leading, y: 0, width: min(input.titleWidth, available), height: metrics.height)
    }
}
