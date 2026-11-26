import AppKit
import Testing
import Theme
@testable import Editor

@MainActor @Suite struct NestedInlineTests {
    nonisolated static let prefixes = [
        "- [ ] 위\n- [ ] ", "- [ ] 위\n  - [ ] ", "- [ ] 위\n    - [ ] ", "- [ ] 위\n\t- [ ] ",
        "- 위\n  - ", "+ 위\n  - [ ] ", "> 위\n  > ", "# 위\n  ",
    ]

    @Test(arguments: prefixes)
    func selectionShortcuts(_ prefix: String) throws {
        typealias Key = EditorShortcuts.Key
        let shortcuts: [(UInt16, String, NSEvent.ModifierFlags, String)] = [
            (Key.b, "b", .command, "**글자**"),
            (Key.x, "X", [.shift, .command], "~~글자~~"),
            (Key.h, "H", [.shift, .command], "==글자=={노랑}"),
            (Key.e, "e", .command, "`글자`"),
            (Key.l, "l", .command, "[글자](https://example.com)"),
        ]
        for (code, character, modifiers, expected) in shortcuts {
            let h = try EditorHarness.at(prefix + "아래 |글자|")
            #expect(h.key(code, character, modifiers))
            if code == Key.l {
                try #require(h.controller.linkSession != nil)
                h.step { h.controller.commitLink("https://example.com") }
            }
            #expect(h.editor.text == prefix + "아래 " + expected)
            #expect(h.beeps == 0)
        }
    }

    @Test(arguments: prefixes)
    func typingBold(_ prefix: String) throws {
        let h = try EditorHarness.at(prefix + "아래 글자|")
        #expect(h.key(EditorShortcuts.Key.b, "b", .command))
        #expect(h.editor.formattingState.bold)
        h.type("가")
        #expect(h.editor.text == prefix + "아래 글자**가**")
        #expect(h.beeps == 0)
    }

    @Test(arguments: prefixes)
    func paragraphSelection(_ prefix: String) throws {
        let suffix = "\n- [ ] 다음"
        let formats: [(EditorAction, String)] = [
            (.bold, "**아래 글자**"), (.strikethrough, "~~아래 글자~~"), (.highlight, "==아래 글자=={노랑}"),
            (.inlineCode, "`아래 글자`"), (.link, "[아래 글자](https://example.com)"),
        ]
        for (action, expected) in formats {
            let h = try EditorHarness.at(prefix + "아래 |글자" + suffix)
            h.view.selectParagraph(nil)
            #expect(h.editor.selectedRange == h.document.lines[1].fullRange)
            let original = h.marked
            h.perform(action)
            if action == .link {
                h.step { h.controller.commitLink("https://example.com") }
            }
            #expect(h.editor.text == prefix + expected + suffix)
            #expect(h.beeps == 0)
            h.undo()
            #expect(h.marked == original)
        }
    }

    @Test func paragraphSelectionOfExistingLinkEditsItsAddress() throws {
        let h = try EditorHarness.at("- 위\n  - [ ] [글|자](https://old.example)\n다음")
        h.view.selectParagraph(nil)
        #expect(h.editor.formattingState.link)
        h.perform(.link)
        try #require(h.controller.linkField.address == "https://old.example")
        h.step { h.controller.commitLink("https://new.example") }
        #expect(h.editor.text == "- 위\n  - [ ] [글자](https://new.example)\n다음")
    }

    @Test func newlineOnlyAndTwoSelectedLinesKeepTheirSource() throws {
        for marked in ["- 위\n  - [ ] 아래|\n|다음", "- 위\n  - [ ] |아래\n다|음"] {
            let h = try EditorHarness.at(marked)
            for action: EditorAction in [.bold, .strikethrough, .highlight, .inlineCode] {
                h.perform(action)
                #expect(h.marked == marked)
            }
            #expect(h.controller.currentLinkTarget == nil)
        }
    }

    @Test(arguments: ["", "  ", "    ", "\t"])
    func storedFormats(_ indent: String) throws {
        let h = try EditorHarness("- [ ] 위\n" + indent + "- [ ] **굵게** ==형광==")
        let line = h.document.lines[1]
        #expect(line.spans.map(\.kind) == [.bold, .highlight(1)])
        let manager = h.controller.layoutManager
        manager.ensureLayout(for: manager.documentRange)
        let location = try #require(h.controller.contentStorage.location(manager.documentRange.location, offsetBy: line.start))
        let fragment = try #require(manager.textLayoutFragment(for: location) as? MarkdownLayoutFragment)
        let shown = try #require((fragment.textElement as? NSTextParagraph)?.attributedString)
        let text = shown.string as NSString
        let bold = shown.attribute(.font, at: text.range(of: "굵게").location, effectiveRange: nil)
        let highlight = shown.attribute(.markdownHighlight, at: text.range(of: "형광").location, effectiveRange: nil)
        #expect(bold as? NSFont == h.theme.nsFont(.strong))
        #expect((highlight as? InlineBackground)?.kind == .highlight(1))

        // 글자 구간만 비트맵에 그려 형광펜 바탕이 실제로 칠해지는지 본다.
        let rect = try #require(fragment.rects(for: text.range(of: "형광")).first).integral
        let context = try #require(CGContext(data: nil, width: Int(rect.width), height: Int(rect.height),
            bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.translateBy(x: -rect.minX, y: rect.maxY)
        context.scaleBy(x: 1, y: -1)
        fragment.drawBackground(at: .zero, in: context)
        fragment.draw(at: .zero, in: context)
        let bitmap = NSBitmapImageRep(cgImage: try #require(context.makeImage()))
        let expected = try #require(h.controller.style.ink(InkColor(.yellow)).usingColorSpace(.deviceRGB))
        let hasBackground = (0..<bitmap.pixelsHigh).contains { y in
            (0..<bitmap.pixelsWide).contains { x in
                guard let pixel = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { return false }
                return pixel.alphaComponent > 0.99 && abs(pixel.redComponent - expected.redComponent) < 0.02
                    && abs(pixel.greenComponent - expected.greenComponent) < 0.02
                    && abs(pixel.blueComponent - expected.blueComponent) < 0.02
            }
        }
        #expect(hasBackground)
    }
}
