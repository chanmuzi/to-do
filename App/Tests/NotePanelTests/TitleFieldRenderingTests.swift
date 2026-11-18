import AppKit
import Testing
import FieldTestSupport
import Theme
@testable import NotePanel

@Suite @MainActor struct TitleFieldRenderingTests {
    @Test func placeholderGeometry() throws {
        _ = FontRegistrar.registerBundledFonts()
        let field = TitleField(style: PanelStyle(theme: try Theme.bundled()))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 200, height: 32),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        window.contentView?.addSubview(field)
        field.show(title: "제목 없음", color: .text3, animated: false)
        field.frame.size = NSSize(width: 180, height: field.idealHeight)
        try FieldGeometry.verify(field, begin: { field.beginEditing(title: "") })
    }

    @Test(arguments: ["오늘 오후 2시", "Title Ag 123"])
    func editingKeepsTheGlyphsInPlace(title: String) throws {
        _ = FontRegistrar.registerBundledFonts()
        let theme = try Theme.bundled()
        let field = TitleField(style: PanelStyle(theme: theme))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 340, height: 28),
                              styleMask: [.borderless], backing: .buffered, defer: true)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let root = TitleTestBackground(frame: window.contentView!.bounds)
        window.contentView = root
        root.addSubview(field)
        field.show(title: title, color: .text, animated: false)
        field.frame = NSRect(x: 12, y: 6, width: 200, height: field.idealHeight)
        func inkBounds() throws -> NSRect {
            root.layoutSubtreeIfNeeded()
            let bitmap = try #require(root.bitmapImageRepForCachingDisplay(in: root.bounds))
            root.cacheDisplay(in: root.bounds, to: bitmap)
            var ink = NSRect.null
            for y in 0..<bitmap.pixelsHigh {
                for x in 0..<bitmap.pixelsWide {
                    if let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB),
                       color.alphaComponent > 0.5, color.redComponent < 0.98 {
                        ink = ink.union(NSRect(x: x, y: y, width: 1, height: 1))
                    }
                }
            }
            return ink
        }
        let before = try inkBounds()
        #expect(!before.isNull)
        field.beginEditing(title: title)
        let editor = try #require(field.currentEditor() as? NSTextView)
        let layout = try #require(editor.layoutManager)
        let container = try #require(editor.textContainer)
        layout.ensureLayout(for: container)
        // 단일 줄 최적화가 켜졌던 셀은 11pt, 편집기는 13pt여서 글자가 들떴다.
        #expect(layout.location(forGlyphAt: 0).y == field.firstBaselineOffsetFromTop)
        let after = try inkBounds()
        // Cell과 NSTextView의 가장 옅은 안티앨리어싱 픽셀은 다를 수 있다.
        // 실제 기준선과 글자 아래쪽 경계, 가로 위치는 한 픽셀도 바뀌지 않아야 한다.
        #expect(after.minX == before.minX)
        #expect(after.maxX == before.maxX)
        #expect(after.maxY == before.maxY)
        field.endEditing()
        #expect(try inkBounds() == before)
    }
}

@MainActor private final class TitleTestBackground: NSView {
    override var isFlipped: Bool { true }
    override func draw(_ dirtyRect: NSRect) { NSColor.white.setFill(); bounds.fill() }
}
