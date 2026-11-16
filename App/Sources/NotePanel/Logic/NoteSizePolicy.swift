import CoreGraphics

/// 노트 창 크기 규칙(spec 5.6, 19). 너비는 사용자가 정하고 높이는 내용을 따른다.
struct NoteSizePolicy: Hashable {
    var defaultWidth: CGFloat
    var minWidth: CGFloat
    var maxWidth: CGFloat
    /// 상단 줄과 그 아래 선의 높이.
    var chromeHeight: CGFloat
    /// 본문 영역의 가장 낮은 높이: 본문 줄 `note-body-lines-min`개와 위아래 여백(D-031).
    /// 글이 그보다 적어도(빈 노트 포함) 본문 영역은 이만큼이다.
    var minBodyHeight: CGFloat
    /// 화면 높이에서 노트가 차지할 수 있는 몫(`note-h-max-screen`, spec 20의 2번 임시 값).
    var maxScreenFraction: CGFloat

    var minHeight: CGFloat { chromeHeight + minBodyHeight }

    func clampedWidth(_ width: CGFloat) -> CGFloat {
        min(max(width, minWidth), maxWidth)
    }

    /// 내용 높이에 맞춘 창 높이. 한도를 넘으면 거기서 멈추고 본문이 스크롤된다.
    /// 한도는 화면 높이의 몫과, 위쪽 가장자리에서 화면 아래 끝까지 남은 높이 가운데 작은 쪽이다
    /// (아래로 늘어난 창이 화면 밖으로 나가지 않게).
    func windowHeight(
        contentHeight: CGFloat, screenHeight: CGFloat, roomBelowTop: CGFloat = .greatestFiniteMagnitude
    ) -> CGFloat {
        let wanted = chromeHeight + max(contentHeight, minBodyHeight)
        let limit = max(minHeight, min(screenHeight * maxScreenFraction, roomBelowTop).rounded(.down))
        return min(wanted, limit).rounded(.up)
    }

    /// 위쪽 가장자리를 `top`에 고정하고 아래로 늘리거나 줄인 틀(AppKit 좌표).
    func frame(
        current: CGRect, top: CGFloat, contentHeight: CGFloat, screenHeight: CGFloat,
        roomBelowTop: CGFloat = .greatestFiniteMagnitude
    ) -> CGRect {
        let height = windowHeight(
            contentHeight: contentHeight, screenHeight: screenHeight, roomBelowTop: roomBelowTop
        )
        return CGRect(x: current.minX, y: top - height, width: clampedWidth(current.width), height: height)
    }
}
