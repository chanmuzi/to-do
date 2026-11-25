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

    /// 펼친 좌표에서 같은 거리만큼 오른쪽으로 물러난다. 상시 보이는 조작은 자기 닫힌 자리로 간다.
    static func drawer(_ input: Input, metrics: Metrics, progress: CGFloat) -> Self {
        var resting = input
        resting.showsControls = false
        var expanded = input
        expanded.showsControls = true
        let closed = Self(resting, metrics: metrics)
        var result = Self(expanded, metrics: metrics)
        let shift: CGFloat
        if !closed.pin.isEmpty { shift = closed.pin.minX - result.pin.minX }
        else if !closed.clock.isEmpty { shift = closed.clock.minX - result.clock.minX }
        else { shift = result.close.maxX - result.pin.maxX }
        func position(_ open: CGRect, from rest: CGRect = .zero) -> CGRect {
            guard !open.isEmpty else { return .zero }
            let delta = rest.isEmpty ? shift : rest.minX - open.minX
            return open.offsetBy(dx: delta * (1 - progress), dy: 0)
        }
        result.agent = position(result.agent, from: closed.agent)
        result.pin = position(result.pin, from: closed.pin)
        result.clock = position(result.clock, from: closed.clock)
        result.more = position(result.more)
        result.divider = position(result.divider)
        result.close = position(result.close)
        if let problem = result.problem { result.problem = position(problem, from: closed.problem ?? .zero) }
        result.title.size.width = closed.title.width + (result.title.width - closed.title.width) * progress
        return result
    }

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
