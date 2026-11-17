import AppKit
import Testing
@testable import Theme

/// 메뉴의 위아래 여백까지 줄과 같은 바탕으로 칠하기(`fillEnclosingMenuBackground`).
/// 실제 메뉴처럼 `NSClipView` 아래 문서 뷰가 있고, 그 안에 줄이 몇 겹 감싸여 들어 있는 모양을 만든다.
@MainActor
@Suite struct MenuBackgroundTests {
    private func makeHierarchy() -> (NSWindow, document: NSView, row: NSView) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 100), styleMask: [.borderless],
            backing: .buffered, defer: true
        )
        window.isReleasedWhenClosed = false
        let clip = NSClipView(frame: NSRect(x: 0, y: 0, width: 200, height: 100))
        let document = NSView(frame: clip.bounds)
        let wrapper = NSView(frame: NSRect(x: 0, y: 5, width: 200, height: 28))
        let row = NSView(frame: wrapper.bounds)
        wrapper.addSubview(row)
        document.addSubview(wrapper)
        clip.documentView = document
        window.contentView?.addSubview(clip)
        return (window, document, row)
    }

    @Test func fillsTheDocumentViewUnderTheClipView() {
        let (window, document, row) = makeHierarchy()
        defer { window.close() }
        let color = CGColor(red: 1, green: 1, blue: 1, alpha: 1)
        row.fillEnclosingMenuBackground(with: color)
        #expect(document.layer?.backgroundColor == color)
    }

    @Test func doesNothingOutsideAWindow() {
        let row = NSView()
        let document = NSView()
        document.addSubview(row)
        row.fillEnclosingMenuBackground(with: CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        #expect(document.layer?.backgroundColor == nil)
    }
}
