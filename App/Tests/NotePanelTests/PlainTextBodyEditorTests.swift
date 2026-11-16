import AppKit
import Testing
import Theme
@testable import NotePanel

@Suite @MainActor struct PlainTextBodyEditorTests {
    private let theme: Theme

    init() throws {
        _ = FontRegistrar.registerBundledFonts()
        theme = try Theme.bundled()
    }

    /// 노트 창이 하듯 너비를 정해 준다.
    private func editor(width: CGFloat = 340) -> (PlainTextBodyEditor, heights: () -> [CGFloat]) {
        let editor = PlainTextBodyEditor(theme: theme)
        var heights: [CGFloat] = []
        editor.onContentHeightChange = { heights.append($0) }
        editor.view.setFrameSize(NSSize(width: width, height: 0))
        return (editor, { heights })
    }

    private var emptyHeight: CGFloat {
        theme.lineHeight(.body) + theme.docPadding.top + theme.docPadding.bottom
    }

    @Test func emptyNoteReportsOneLinePlusPadding() {
        let (_, heights) = editor()
        #expect(heights() == [emptyHeight])
    }

    @Test func heightGrowsByOneLineHeightPerLine() {
        let (editor, heights) = editor()
        editor.text = "하나\n둘\n셋"
        #expect(heights().last == emptyHeight + theme.lineHeight(.body) * 2)
    }

    @Test func narrowerWidthWrapsAndReportsATallerHeight() {
        let (editor, heights) = editor(width: 560)
        editor.text = String(repeating: "긴 한 줄은 줄바꿈합니다 ", count: 8)
        let wide = heights().last ?? 0
        editor.view.setFrameSize(NSSize(width: 260, height: editor.view.frame.height))
        #expect((heights().last ?? 0) > wide)
    }

    @Test func settingTextFromOutsideDoesNotReportAUserEdit() {
        let (editor, _) = editor()
        var edits: [String] = []
        editor.onTextChange = { edits.append($0) }
        editor.text = "밖에서 넣은 글"
        #expect(editor.text == "밖에서 넣은 글")
        #expect(edits.isEmpty)
    }

    @Test func typingReportsTheNewText() throws {
        let (editor, _) = editor()
        var edits: [String] = []
        editor.onTextChange = { edits.append($0) }
        let textView = try #require(editor.view as? NSTextView)
        textView.insertText("가", replacementRange: NSRange(location: 0, length: 0))
        #expect(edits == ["가"])
    }

    @Test func bodyFontComesFromTheThemeAndContentStacksFromTheTop() throws {
        let (editor, _) = editor()
        let textView = try #require(editor.view as? NSTextView)
        #expect(textView.font == theme.nsFont(.body))
        #expect(textView.isFlipped)
    }
}
