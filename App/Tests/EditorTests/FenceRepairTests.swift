import AppKit
import Testing
@testable import Editor

/// ``` 줄의 짝을 잃게 하는 편집(D-036의 5번). 넣을 수 있게 고쳐서 넣고, 고칠 수 없을 때만 넣지 않되 알린다.
@MainActor
@Suite struct FenceRepairTests {
    private func kinds(_ h: EditorHarness) -> [LineKind] { h.document.lines.map(\.kind) }

    /// 화면에 보이는 글자(감춘 기호와 백슬래시를 뺀 것).
    private func visible(_ h: EditorHarness, line index: Int) -> String {
        let line = h.document.lines[index]
        let hidden = line.markers.map(\.range)
        let units = (line.contentStart..<line.end).filter { position in !hidden.contains { NSLocationInRange(position, $0) } }
            .map { h.document.units[$0] }
        return String(utf16CodeUnits: units, count: units.count)
    }

    /// 글자로 보이던 백틱이 줄 머리에 놓이게 되는 지우기: 첫 백틱을 막아 글자로 남긴다.
    @Test func deletingTheTextBeforeLiteralBackticksKeepsThemLiteral() throws {
        let h = try EditorHarness.at("a|```\n글")
        h.press(NSResponder.backspace)
        #expect(h.marked == "|\\```\n글")
        #expect(kinds(h) == [.paragraph, .paragraph])
        #expect(visible(h, line: 0) == "```")
        #expect(h.beeps == 0)
        // 한 단계다.
        h.undo()
        #expect(h.marked == "a|```\n글")
        #expect(!h.editor.undoManager.canUndo)
        h.redo()
        #expect(h.editor.text == "\\```\n글")
    }

    @Test func deletingASelectionBeforeLiteralBackticksKeepsThemLiteral() throws {
        let h = try EditorHarness.at("|x |``` y\n글")
        h.press(NSResponder.backspace)
        #expect(h.marked == "|\\``` y\n글")
        #expect(visible(h, line: 0) == "``` y")
        #expect(h.beeps == 0)
        // 덮어써도 같다.
        let k = try EditorHarness.at("|x |``` y\n글")
        k.type("\t")
        #expect(!EditorCommands.hasUnterminatedFence(k.document))
        // 줄을 합쳐 ``` 가 되는 지우기도 같다.
        let j = try EditorHarness.at("``\n|`\n글")
        j.press(NSResponder.backspace)
        #expect(j.editor.text == "\\```\n글")
        #expect(visible(j, line: 0) == "```")
    }

    /// 백틱 둘의 앞이나 사이에 친 세 번째 백틱도 코드 블록을 만든다(끝에 친 것과 같다).
    @Test func thirdBacktickTypedBeforeOrBetweenTheOtherTwoMakesABlock() throws {
        for start in ["글\n|``\n글", "글\n`|`\n글", "글\n``|\n글"] {
            let h = try EditorHarness.at(start)
            h.type("`")
            #expect(h.marked == "글\n```\n|\n```\n글", "\(start)")
            #expect(kinds(h) == [.paragraph, .fenceOpen, .code, .fenceClose, .paragraph])
            #expect(h.beeps == 0)
            h.undo()
            #expect(h.editor.text == "글\n``\n글")
        }
        // 뒤에 글이 있으면 그 글이 코드 줄이 된다.
        let k = try EditorHarness.at("|``let a\n글")
        k.type("`")
        #expect(k.marked == "```\n|let a\n```\n글")
    }

    /// 코드 블록 안에서는 백슬래시도 글자여서 막을 수 없다. 넣지 않고 알린다.
    @Test func unrepairableEditsAreRejectedWithTheBeep() throws {
        let h = try EditorHarness.at("```\n|x```\n```\n뒤")
        h.press(NSResponder.forwardDelete)
        #expect(h.editor.text == "```\nx```\n```\n뒤")
        #expect(h.beeps == 1)
        // 보이지 않는 ``` 줄의 한쪽만 지우는 편집.
        let k = try EditorHarness.at("앞\n```\n코|드\n```\n뒤|")
        let before = k.editor.text
        k.step { k.view.insertText("", replacementRange: NSRange(location: 2, length: 5)) }
        #expect(k.editor.text == before)
        #expect(k.beeps == 1)
    }
}

/// 세 번째 백틱 바로 뒤의 낱말은 아는 언어 이름일 때만 언어 이름이 된다.
@MainActor
@Suite struct LanguageTagTests {
    @Test(arguments: ["ls", "x", "main", "hello", "abc123"])
    func otherWordsStayCodeLines(word: String) throws {
        let h = try EditorHarness()
        h.type("```" + word)
        h.press(NSResponder.newline)
        #expect(h.marked == "```\n\(word)\n|\n```")
        #expect(h.document.lines.map(\.kind) == [.fenceOpen, .code, .code, .fenceClose])
    }

    @Test(arguments: ["swift", "py", "json", "c++", "objective-c", "c#", "Swift", "JSON", "plaintext", "sh"])
    func knownLanguagesBecomeTheTag(word: String) throws {
        let h = try EditorHarness()
        h.type("```" + word)
        h.press(NSResponder.newline)
        #expect(h.marked == "```\(word)\n|\n```")
    }

    @Test func theListCoversTheCommonNames() {
        let expected = [
            "swift", "objc", "c", "cpp", "rust", "go", "python", "py", "javascript", "js", "typescript", "ts", "tsx", "jsx",
            "json", "yaml", "yml", "toml", "html", "css", "scss", "sql", "bash", "sh", "zsh", "shell", "ruby", "rb", "java",
            "kotlin", "php", "lua", "r", "dart", "diff", "markdown", "md", "xml", "plaintext", "text",
        ]
        #expect(expected.allSatisfy(CodeLanguages.isKnown))
        #expect(!CodeLanguages.isKnown("ls"))
        #expect(!CodeLanguages.isKnown(""))
    }
}
