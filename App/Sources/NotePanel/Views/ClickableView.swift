import AppKit

/// 누를 수 있는 것의 바탕(규칙 9): 그 위에서도 마우스는 화살표다.
/// 본문 위에 겹쳐 뜨는 버튼(휴지통, 닫기)에 글자 칸의 I자 커서가 비치지 않도록 제 영역의 커서를 화살표로 밝힌다.
class ClickableView: NSView {
    /// 마지막으로 밝힌 커서 영역.
    private(set) var declaredCursorRects: [NSRect] = []

    override func resetCursorRects() {
        declaredCursorRects = [bounds]
        addCursorRect(bounds, cursor: .arrow)
    }

    /// 커서 영역이 꺼져 있을 때 오는 알림. 아래에 깔린 글자 칸으로 넘기지 않고 화살표로 정한다.
    override func cursorUpdate(with event: NSEvent) {
        NSCursor.arrow.set()
    }
}
