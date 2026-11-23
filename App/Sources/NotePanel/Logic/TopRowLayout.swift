import CoreGraphics

/// 상단 조작은 오른쪽부터 배치하고 남은 너비를 제목과 예정 칩에 쓴다.
struct TopRowLayout: Hashable {
    struct Metrics: Hashable {
        var height: CGFloat
        var paddingLeading: CGFloat
        var paddingTrailing: CGFloat
        var gap: CGFloat
        var iconButton: CGFloat
        /// 나란히 놓인 아이콘 버튼 사이(`icon-btn-gap`). 버튼은 평소 상자 없이 아이콘만 보이므로(규칙 10)
        /// 보이는 간격은 아이콘 사이의 거리다. 이웃한 버튼의 `hover` 상자는 겹치지 않고 맞닿는다.
        var dividerWidth: CGFloat = 1
        var buttonGap: CGFloat = 0
    }

    struct Input: Hashable {
        var width: CGFloat
        /// 제목이 다 보이는 너비.
        var titleWidth: CGFloat
        var reminderWidth: CGFloat?
        var hasSchedules = true
        var showsControls = true
        var allowsAgent = true
        var hasAgentActivity = false
        var isPinned = false
        var showsProblem: Bool
    }

    var title: CGRect
    var more: CGRect
    var problem: CGRect?
    var reminder: CGRect?
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
        if input.hasSchedules && input.showsControls && input.reminderWidth == nil {
            clock = takeTrailing(metrics.iconButton, gap: metrics.buttonGap)
        }
        let showsAgent = input.allowsAgent && (input.showsControls || input.hasAgentActivity)
        if let width = input.reminderWidth {
            let gap = showsPin ? metrics.gap : 0
            let faceSpace = showsAgent ? metrics.iconButton + metrics.buttonGap : 0
            let reserved = faceSpace + metrics.paddingLeading + metrics.gap + (input.showsProblem ? metrics.iconButton + metrics.buttonGap : 0)
            reminder = takeTrailing(min(width, max(0, trailing - reserved - gap)), gap: gap)
        }
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
