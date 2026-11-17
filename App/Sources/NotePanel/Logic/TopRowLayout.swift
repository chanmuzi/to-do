import CoreGraphics

/// 상단 줄 요소의 자리(spec 5.1, 5.2). 호버로 나타나는 것도 늘 자리를 차지하고,
/// 좁아지면 제목이 먼저 줄어든다(spec 16). 호버와 포커스는 입력이 아니다.
///
/// 저장 문제 표시는 호버 아이콘 둘의 왼쪽, 제목 쪽에 놓는다. 표시가 나타나고 사라져도
/// 자리를 미리 차지하는 것들(호버 아이콘, 리마인더, 핀)은 움직이지 않고 제목이 잘리는 자리만 달라진다(규칙 7).
struct TopRowLayout: Hashable {
    struct Metrics: Hashable {
        var height: CGFloat
        var paddingLeading: CGFloat
        var paddingTrailing: CGFloat
        var gap: CGFloat
        var iconButton: CGFloat
        /// 나란히 놓인 아이콘 버튼 사이(`icon-btn-gap`). 버튼은 평소 상자 없이 아이콘만 보이므로(규칙 10)
        /// 보이는 간격은 아이콘 사이의 거리다. 이웃한 버튼의 `hover` 상자는 겹치지 않고 맞닿는다.
        var buttonGap: CGFloat = 0
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
    var more: CGRect
    var add: CGRect
    var problem: CGRect?
    var reminder: CGRect?
    var pin: CGRect

    init(_ input: Input, metrics: Metrics) {
        let buttonY = ((metrics.height - metrics.iconButton) / 2).rounded()
        var trailing = input.width - metrics.paddingTrailing
        // 바로 앞(오른쪽)에 놓인 것이 아이콘 버튼인지. 버튼끼리는 `buttonGap`, 그 밖은 `gap`만큼 띄운다.
        var previousIsButton = false
        func takeTrailing(_ width: CGFloat, isButton: Bool) -> CGRect {
            if trailing < input.width - metrics.paddingTrailing {
                trailing -= previousIsButton && isButton ? metrics.buttonGap : metrics.gap
            }
            let rect = CGRect(x: trailing - width, y: buttonY, width: width, height: metrics.iconButton)
            trailing = rect.minX
            previousIsButton = isButton
            return rect
        }

        pin = takeTrailing(metrics.iconButton, isButton: true)
        reminder = input.reminderWidth.map { takeTrailing($0, isButton: false) }
        add = takeTrailing(metrics.iconButton, isButton: true)
        more = takeTrailing(metrics.iconButton, isButton: true)
        problem = input.showsProblem ? takeTrailing(metrics.iconButton, isButton: true) : nil
        trailing -= metrics.gap

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
