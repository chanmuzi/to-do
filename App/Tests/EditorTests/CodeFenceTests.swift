import AppKit
import Testing
@testable import Editor

/// 코드 블록의 ``` 줄은 보이지 않는다. 그래서 짝을 잃거나, 사용자가 지울 수 없는 ``` 줄이 생기지 않아야 한다.
@MainActor
@Suite struct CodeFenceTests {
    private func kinds(_ h: EditorHarness) -> [LineKind] { h.document.lines.map(\.kind) }

    /// 블록 안의 빈 줄에서 친 백틱 셋은 블록에서 나간다(빈 마지막 줄의 Return과 같다).
    @Test func thirdBacktickOnAnEmptyLineInsideABlockLeavesIt() throws {
        let h = try EditorHarness.at("```\ncode\n|\n```\nafter **b**")
        h.type("```")
        #expect(h.marked == "```\ncode\n```\n|\nafter **b**")
        #expect(kinds(h) == [.fenceOpen, .code, .fenceClose, .paragraph, .paragraph])
        #expect(h.document.lines[4].spans.map(\.kind) == [.bold])
        h.undo()
        #expect(h.marked == "```\ncode\n``|\n```\nafter **b**")
    }

    /// 블록 안의 다른 자리에서 백틱은 글자다. 그 줄이 ``` 줄로 읽히게 되는 입력은 들어가지 않는다.
    @Test func backticksElsewhereInsideABlockStayLiteral() throws {
        let h = try EditorHarness.at("```\nx|\n```\n뒤")
        h.type("```")
        #expect(h.marked == "```\nx```|\n```\n뒤")
        #expect(kinds(h) == [.fenceOpen, .code, .fenceClose, .paragraph])
        // 줄 맨 앞에 쳐도 뒤에 글이 있으면 글자다.
        let k = try EditorHarness.at("```\n|x\n```\n뒤")
        k.type("```")
        #expect(k.marked == "```\n```|x\n```\n뒤")
        #expect(kinds(k) == [.fenceOpen, .code, .fenceClose, .paragraph])
        // 그 글을 지워 ``` 만 남기는 편집은 넣지 않는다(새 닫는 줄이 되어 아래가 모두 뒤집힌다).
        k.press(NSResponder.forwardDelete)
        #expect(k.editor.text == "```\n```x\n```\n뒤")
        #expect(!EditorCommands.hasUnterminatedFence(k.document))
    }

    @Test func pastedFencedBlockIsPutOnItsOwnLines() throws {
        let h = try EditorHarness.at("메모: |\n다음 **줄**\n끝")
        h.paste("```\ncode\n```")
        #expect(h.editor.text == "메모: \n```\ncode\n```\n다음 **줄**\n끝")
        #expect(kinds(h) == [.paragraph, .fenceOpen, .code, .fenceClose, .paragraph, .paragraph])
        h.undo()
        #expect(h.editor.text == "메모: \n다음 **줄**\n끝")
        // 줄 가운데에 붙이면 뒤의 글도 제 줄로 내려간다.
        let k = try EditorHarness.at("앞|뒤")
        k.paste("```\ncode\n```")
        #expect(k.editor.text == "앞\n```\ncode\n```\n뒤")
    }

    @Test func pastedUnterminatedFenceIsClosedInTheSameEdit() throws {
        let h = try EditorHarness.at("가\n|\n다음 **줄**")
        h.paste("```")
        #expect(h.editor.text == "가\n```\n```\n다음 **줄**")
        #expect(!EditorCommands.hasUnterminatedFence(h.document))
        #expect(h.document.lines[3].spans.map(\.kind) == [.bold])
        let k = try EditorHarness.at("가\n|\n다음")
        k.paste("```swift\nlet a = 1")
        #expect(k.editor.text == "가\n```swift\nlet a = 1\n```\n다음")
        k.undo()
        #expect(k.editor.text == "가\n\n다음")
    }

    @Test func pastingAFencedBlockInsideABlockKeepsOnlyTheCode() throws {
        let h = try EditorHarness.at("```\na\n|\n```\n뒤")
        h.paste("```\ncode\n```")
        #expect(h.editor.text == "```\na\ncode\n```\n뒤")
        #expect(kinds(h) == [.fenceOpen, .code, .code, .fenceClose, .paragraph])
    }

    @Test func selectAllAndDeleteAlwaysEmptiesTheDocument() throws {
        for text in [
            "```\ncode\n```", "앞\n```\ncode\n```\n뒤", "```\n```", "- 항목\n```swift\nx\n```", "```\n닫히지 않음", "# 제목\n- [ ] 할 일",
        ] {
            let h = try EditorHarness(text)
            h.step { h.view.selectAll(nil) }
            h.press(NSResponder.backspace)
            #expect(h.editor.text.isEmpty, "\(text)")
            h.undo()
            #expect(h.editor.text == text)
        }
    }

    /// 블록의 경계는 첫 줄 맨 앞의 ⌫와 마지막 줄 끝의 ⌦로 지운다.
    @Test func blockBoundaryIsRemovedWithOrdinaryKeys() throws {
        let h = try EditorHarness.at("앞\n```\n|하나\n둘\n```\n뒤")
        h.press(NSResponder.backspace)
        #expect(h.marked == "앞\n|하나\n둘\n뒤")
        h.undo()
        #expect(h.editor.text == "앞\n```\n하나\n둘\n```\n뒤")
        let k = try EditorHarness.at("앞\n```\n하나\n둘|\n```\n뒤")
        k.press(NSResponder.forwardDelete)
        #expect(k.marked == "앞\n하나\n둘|\n뒤")
    }

    /// 닫는 줄이 없는 파일: 그대로 읽고(문서 끝까지 코드), 고칠 수 있고, 닫거나 없앨 수 있다.
    @Test func foreignUnterminatedFenceLoadsUndamagedAndStaysEditable() throws {
        let source = "앞\n```js\nlet a = 1\nlet b = 2"
        let h = try EditorHarness(source)
        #expect(h.editor.text == source)
        #expect(h.changes.isEmpty)
        #expect(kinds(h) == [.paragraph, .fenceOpen, .code, .code])
        // 고칠 수 있다(닫는 줄을 몰래 넣지 않는다).
        h.caret(at: h.document.length)
        h.type(";")
        #expect(h.editor.text == source + ";")
        // 빈 마지막 줄에서 Return을 누르면 닫는 줄을 넣고 블록 아래로 나간다.
        h.press(NSResponder.newline)
        h.press(NSResponder.newline)
        #expect(h.marked == source + ";\n```\n|")
        #expect(!EditorCommands.hasUnterminatedFence(h.document))
        // 없애기: 첫 줄 맨 앞의 ⌫가 여는 줄을 지운다.
        let k = try EditorHarness(source)
        k.caret(at: k.document.lines[2].start)
        k.press(NSResponder.backspace)
        #expect(k.marked == "앞\n|let a = 1\nlet b = 2")
        // ↓로도 닫고 나갈 수 있다.
        let d = try EditorHarness(source)
        d.caret(at: d.document.length)
        d.press(NSResponder.down)
        #expect(d.marked == source + "\n```\n|")
    }

    // MARK: 줄이 없는 블록

    @Test func moveLineNeverCarriesALineAcrossAFence() throws {
        let h = try EditorHarness.at("a\n```\n|x\n```\nb")
        h.perform(.moveLineUp)
        #expect(h.editor.text == "a\n```\nx\n```\nb")
        h.perform(.moveLineDown)
        #expect(h.editor.text == "a\n```\nx\n```\nb")
        // 블록 안에서는 줄끼리 자리를 바꾼다.
        let k = try EditorHarness.at("```\n하나\n|둘\n```")
        k.perform(.moveLineUp)
        #expect(k.marked == "```\n|둘\n하나\n```")
        // 블록 밖의 줄은 블록을 통째로 건너뛴다.
        let m = try EditorHarness.at("|a\n```\nx\n```\nb")
        m.perform(.moveLineDown)
        #expect(m.marked == "```\nx\n```\n|a\nb")
        m.perform(.moveLineUp)
        #expect(m.marked == "|a\n```\nx\n```\nb")
    }

    @Test func emptyBlockFromAForeignFileCanBeEnteredAndTypedIn() throws {
        let h = try EditorHarness("a\n```\n```\nb")
        h.caret(at: 1)
        h.press(NSResponder.right)
        // 닫는 줄의 맨 앞이 그 블록의 커서 자리다(빈 코드 줄로 보인다).
        #expect(h.marked == "a\n```\n|```\nb")
        #expect(h.changes.isEmpty)
        h.type("x")
        #expect(h.marked == "a\n```\nx|\n```\nb")
        #expect(kinds(h) == [.paragraph, .fenceOpen, .code, .fenceClose, .paragraph])
        // 위아래로 지나갈 수 있다.
        let k = try EditorHarness("a\n```\n```\nb")
        k.caret(at: k.document.length)
        k.press(NSResponder.left)
        k.press(NSResponder.left)
        #expect(k.marked == "a\n```\n|```\nb")
        k.press(NSResponder.left)
        #expect(k.marked == "a|\n```\n```\nb")
        k.press(NSResponder.right)
        k.press(NSResponder.right)
        #expect(k.marked == "a\n```\n```\n|b")
    }

    @Test func emptyBlockIsDeletedFromInsideAndFromEitherSide() throws {
        let inside = try EditorHarness("a\n```\n```\nb")
        inside.place(at: 6)
        inside.press(NSResponder.backspace)
        #expect(inside.marked == "a\n|b")
        let below = try EditorHarness.at("a\n```\n```\n|b")
        below.press(NSResponder.backspace)
        #expect(below.marked == "a\n|b")
        let above = try EditorHarness.at("a|\n```\n```\nb")
        above.press(NSResponder.forwardDelete)
        #expect(above.marked == "a|\nb")
        above.undo()
        #expect(above.editor.text == "a\n```\n```\nb")
    }

    // MARK: 언어 이름

    @Test func wordTypedRightAfterTheThirdBacktickBecomesTheLanguageTag() throws {
        let h = try EditorHarness()
        h.type("```swift")
        #expect(h.marked == "```\nswift|\n```")
        h.press(NSResponder.newline)
        #expect(h.marked == "```swift\n|\n```")
        #expect(kinds(h) == [.fenceOpen, .code, .fenceClose])
        // 그다음 Return은 보통의 줄바꿈이다(한 번만 삼킨다).
        h.type("let a = 1")
        h.press(NSResponder.newline)
        #expect(h.marked == "```swift\nlet a = 1\n|\n```")
        // 되돌리면 낱말이 코드 줄로 돌아온다.
        let k = try EditorHarness()
        k.type("```c++")
        k.press(NSResponder.newline)
        #expect(k.marked == "```c++\n|\n```")
        k.undo()
        #expect(k.marked == "```\nc++|\n```")
    }

    @Test func returnOrSpaceRightAfterTheThirdBacktickIsSwallowedOnce() throws {
        let h = try EditorHarness()
        h.type("```")
        h.press(NSResponder.newline)
        #expect(h.marked == "```\n|\n```")
        // 삼킨 뒤에 친 낱말은 코드다. 빈 첫 줄을 뜻한 Return은 그대로 들어간다.
        h.press(NSResponder.newline)
        #expect(h.marked == "```\n\n|\n```")
        let k = try EditorHarness()
        k.type("```")
        k.press(NSResponder.newline)
        k.type("ls")
        k.press(NSResponder.newline)
        #expect(k.marked == "```\nls\n|\n```")
        // 낱말이 아닌 글(공백이 들었다)은 언어 이름이 아니다.
        let m = try EditorHarness()
        m.type("```let a")
        m.press(NSResponder.newline)
        #expect(m.marked == "```\nlet a\n|\n```")
        // 글이 있는 줄을 감싼 블록에서는 언어 이름을 받지 않는다.
        let w = try EditorHarness.at("``|항목")
        w.type("`")
        w.type("x")
        w.press(NSResponder.newline)
        #expect(w.marked == "```\nx\n|항목\n```")
    }
}
