import AppKit

/// 앱이 붙이는 정보 글자(시간 등) 한 줄. 잰 폭 그대로 왼쪽 끝에서 그리고 세로로는 가운데에 둔다.
/// 시스템 레이블은 양옆에 제 여백을 넣어, 굵기만 바뀌어도 글자가 잘리거나 밀린다.
final class InfoLabel: NSView {
    private var text = NSAttributedString()

    func set(text: String, font: NSFont, color: NSColor) {
        self.text = NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: color])
        needsDisplay = true
    }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        let size = text.size()
        text.draw(at: NSPoint(x: 0, y: ((bounds.height - size.height) / 2).rounded()))
    }
}
