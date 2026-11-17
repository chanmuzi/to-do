import AppKit

/// 누를 수 있는 것의 바탕(규칙 9): 그 위에서도 마우스는 화살표다.
/// 본문 위에 겹쳐 뜨는 버튼(휴지통, 닫기)에 글자 칸의 I자 커서가 비치지 않도록 제 영역의 커서를 화살표로 밝힌다.
///
/// 누름은 언제나 이 뷰가 통째로 받는다. 안에 든 아이콘(`NSImageView`)이나 글자(`NSTextField`)가 누름을 받으면
/// 두 가지 길로 누름이 사라졌다: 아이콘 뷰는 `acceptsFirstMouse`가 거짓이라 키 창이 아니거나 앱이 앞에 있지
/// 않을 때의 첫 누름을 AppKit이 버렸고, 위로 올려 보내는 동안 뗀 이벤트가 이 뷰에 오지 않을 수 있었다.
/// 노트 창은 이 뷰로 가는 누름을 창의 크기 조절이나 끌기보다 먼저 이 뷰에 건넨다(`NotePanelWindow.sendEvent`).
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

    /// 안에 든 뷰가 아니라 언제나 이 뷰가 누름을 받는다. `point`는 위 뷰의 좌표다.
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard !isHidden, frame.contains(point) else { return nil }
        return self
    }

    override var mouseDownCanMoveWindow: Bool { false }

    /// 키 창이 아니어도, 앱이 앞에 있지 않아도 첫 누름이 동작한다.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
