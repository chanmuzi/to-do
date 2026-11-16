#if DEBUG
import AppKit

/// 확인용: 노트 창 뒤에 까는 불투명한 단색 창. 노트 창 바깥에 그려지는 것(그림자, 모서리 밖의 잔상)을
/// 사용자의 화면을 찍지 않고 보기 위한 것이다. 이 창 안쪽만 화면 영역으로 찍는다.
/// 고정된 노트(`.floating`) 바로 아래 단계에 뜨고 마우스를 받지 않는다.
final class DebugBackdrop {
    private var window: NSWindow?

    /// 주어진 창 틀들을 여백과 함께 덮는 자리에 깐다.
    /// - Returns: 찍을 영역(`screencapture -R`의 좌표: 주 화면의 왼쪽 위가 원점). 덮을 것이 없으면 `nil`.
    func show(color: NSColor, around frames: [NSRect], margin: CGFloat = 70) -> NSRect? {
        hide()
        guard let first = frames.first, let primary = NSScreen.screens.first else { return nil }
        let frame = frames.dropFirst().reduce(first) { $0.union($1) }.insetBy(dx: -margin, dy: -margin)
        let backdrop = NSWindow(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
        backdrop.isReleasedWhenClosed = false
        backdrop.isOpaque = true
        backdrop.backgroundColor = color
        backdrop.hasShadow = false
        backdrop.ignoresMouseEvents = true
        backdrop.level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue - 1)
        backdrop.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        backdrop.orderFrontRegardless()
        window = backdrop
        let inner = frame.insetBy(dx: 2, dy: 2)
        return NSRect(x: inner.minX, y: primary.frame.height - inner.maxY, width: inner.width, height: inner.height)
    }

    func hide() {
        window?.close()
        window = nil
    }
}
#endif
