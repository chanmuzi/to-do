import AppKit
@testable import Editor
import Foundation
import Testing
import Theme
@testable import FloatingNotes

/// 단축키 표(`ShortcutTable`)가 `tokens.json`의 `shortcuts`(spec 13)와 줄마다 같은지, 메뉴 막대 메뉴와
/// 표시 기본값이 토큰과 같은지.
@Suite struct ShortcutTableTests {
    private struct TokenGroup: Equatable {
        var group: String
        var items: [TokenItem]
    }

    private struct TokenItem: Equatable {
        var action: String
        var keys: [String]
    }

    private func tokens() throws -> [String: Any] {
        let data = try Data(contentsOf: ThemeResources.tokensURL())
        return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func tokenShortcuts() throws -> [TokenGroup] {
        let raw = try #require(try tokens()["shortcuts"] as? [[String: Any]])
        return try raw.map { group in
            TokenGroup(
                group: try #require(group["group"] as? String),
                items: try #require(group["items"] as? [[String: Any]]).map { item in
                    TokenItem(
                        action: try #require(item["action"] as? String), keys: try #require(item["keys"] as? [String])
                    )
                }
            )
        }
    }

    @Test func tableMatchesTheTokensLineForLine() throws {
        let expected = try tokenShortcuts()
        let actual = ShortcutGroup.allCases.map { group in
            TokenGroup(
                group: group.rawValue,
                items: ShortcutTable.standard.entries(in: group).map {
                    TokenItem(action: $0.action, keys: $0.keyLabels)
                }
            )
        }

        #expect(actual.map(\.group) == expected.map(\.group))
        for (mine, theirs) in zip(actual, expected) {
            #expect(mine.items == theirs.items, "\(mine.group)")
        }
        #expect(ShortcutTable.standard.entries.count == expected.reduce(0) { $0 + $1.items.count })
    }

    /// App이 받는 동작은 "어디서나"와 "노트 창" 구획의 모든 줄이고, 동작마다 줄이 하나다.
    @Test func everyGlobalAndNoteWindowRowHasExactlyOneCommand() {
        let table = ShortcutTable.standard
        let bound = table.entries.compactMap(\.command)
        #expect(Set(bound) == Set(AppCommand.allCases))
        #expect(bound.count == AppCommand.allCases.count)
        for entry in table.entries {
            let isAppRow = [.global, .noteWindow].contains(entry.group) || (entry.group == .agent && entry.chords.first?.key == .j)
            #expect((entry.command != nil) == isAppRow, "\(entry.action)")
        }
        #expect(table.entries(in: .global).allSatisfy { $0.chords.first?.modifiers == [.control, .option] })
        // ⌃⌥Space는 쓰지 않는다(입력 소스 전환과 겹침, spec 13).
        #expect(!table.entries.contains { $0.chords.contains(KeyChord(.space, [.control, .option])) })
    }

    /// 같은 곳에서 듣는 키가 겹치지 않는다: App이 받는 것끼리, 그리고 편집기가 먼저 받는 "편집" 줄과.
    @Test func chordsDoNotCollideWithinTheNoteWindow() {
        let table = ShortcutTable.standard
        let editing = table.entries(in: .editing).filter { $0.action != "현재 줄 날짜 제안 받기" }
        let heard = (table.entries(in: .global) + table.entries(in: .noteWindow) + table.entries(in: .agent).filter { $0.command != nil } + editing)
            .flatMap(\.chords)
        #expect(Set(heard).count == heard.count)
        // 앱 메뉴가 따로 듣는 표준 편집 키와도 겹치지 않는다.
        let standard = [
            KeyChord(.z, .command), KeyChord(.z, [.shift, .command]), KeyChord(.x, .command),
            KeyChord(.c, .command), KeyChord(.v, .command), KeyChord(.a, .command), KeyChord(.q, .command),
        ]
        #expect(Set(heard).isDisjoint(with: standard))
    }

    @Test func chordLabelsFollowTheMacOrderAndKeyCodesAreDistinct() {
        #expect(KeyChord(.t, [.command, .shift]).labels == ["⇧", "⌘", "T"])
        #expect(KeyChord(.n, [.option, .control]).labels == ["⌃", "⌥", "N"])
        #expect(KeyChord(.returnKey, .command).labels == ["⌘", "↵"])
        #expect(Set(ShortcutKey.allCases.map(\.keyCode)).count == ShortcutKey.allCases.count)
        #expect(ShortcutModifiers([.control, .option]).eventFlags == [.control, .option])
    }

    /// 뒤 단계의 설정이 키를 바꿀 때 쓰는 길: 그 동작의 줄만 바뀐 표가 나온다.
    @Test func replacingAChordChangesOnlyThatCommand() {
        let chord = KeyChord(.k, [.control, .option])
        let changed = ShortcutTable.standard.replacing(.quickCapture, with: chord)

        #expect(changed.chord(for: .quickCapture) == chord)
        #expect(changed.entry(for: .quickCapture)?.keyLabels == ["⌃", "⌥", "K"])
        #expect(changed.chord(for: .library) == ShortcutTable.standard.chord(for: .library))
        #expect(changed.entries.count == ShortcutTable.standard.entries.count)
    }

    // MARK: - 다른 토큰과 견주는 것

    @Test func statusMenuFollowsTheNavigationTokens() throws {
        let navigation = try #require(try tokens()["navigation"] as? [String: Any])
        let expected = try #require(navigation["menuBar"] as? [String])

        #expect(StatusMenuModel.entries(areNotesHidden: false).compactMap(\.title) == expected)
    }

    @Test func editorOptionsDefaultToTheDisplayTokens() throws {
        let display = try #require(try tokens()["display"] as? [String: Any])
        let defaults = try #require(display["defaults"] as? [String: String])
        let all = try #require(display["checkbox"] as? [String])

        #expect(NoteEditorOptions().checkbox.rawValue == defaults["checkbox"])
        #expect(CheckboxStyle.allCases.map(\.rawValue) == all)
    }

    // MARK: - 편집기의 키와 견주는 것

    /// "편집" 줄은 두 곳에 있다: 보여 주는 표(`ShortcutTable`)와 편집기가 실제로 듣는 키(`EditorShortcuts`).
    /// 한쪽만 고치면 표에 적힌 키가 듣지 않거나 표에 없는 키가 듣는다. 줄마다 키 자리, 보조 키, 동작이 같아야 한다.
    @Test func editingRowsMatchTheKeysTheEditorActuallyHears() throws {
        let expected: [String: [EditorAction]] = [
            "투두로 바꾸기": [.toggleTodo],
            "완료 표시, 토글 접기와 펼치기": [.toggleDone],
            "블록 복제": [.duplicate],
            "줄 위로, 아래로 옮기기": [.moveLineUp, .moveLineDown],
            "접기, 펼치기": [.fold, .unfold],
            "제목 1, 2, 3": [.heading(1), .heading(2), .heading(3)],
            "굵게": [.bold],
            "취소선": [.strikethrough],
            "형광펜 (다시 누르면 다음 색)": [.highlight],
            "인라인 코드": [.inlineCode],
            "코드 블록": [.codeBlock],
            "링크": [.link],
        ]
        func modifiers(_ chord: KeyChord) -> EditorShortcuts.Modifiers {
            var result: EditorShortcuts.Modifiers = []
            if chord.modifiers.contains(.command) { result.insert(.command) }
            if chord.modifiers.contains(.shift) { result.insert(.shift) }
            if chord.modifiers.contains(.option) { result.insert(.option) }
            if chord.modifiers.contains(.control) { result.insert(.control) }
            return result
        }
        // Tab, ⇧Tab은 편집기가 글자 입력 경로에서 받는다(단축키 목록에 없다).
        let typed: Set<String> = ["들여쓰기 (여러 줄 선택 또는 날짜 제안이 없을 때)", "내어쓰기 / 본문 처음에서 제목으로", "현재 줄 날짜 제안 받기", "날짜 제안 닫기, 블록 고르기 또는 풀기", "같은 블록 안에서 줄바꿈"]
        let rows = ShortcutTable.standard.entries(in: .editing).filter { !typed.contains($0.action) }
        #expect(ShortcutTable.standard.entries(in: .editing).count == rows.count + typed.count)
        #expect(Set(rows.map(\.action)) == Set(expected.keys))

        var fromTable: Set<EditorShortcuts.Binding> = []
        for row in rows {
            let actions = try #require(expected[row.action], "\(row.action)")
            #expect(row.chords.count == actions.count, "\(row.action)")
            for (chord, action) in zip(row.chords, actions) {
                #expect(
                    EditorShortcuts.action(keyCode: chord.key.keyCode, modifiers: modifiers(chord)) == action,
                    "\(row.action) \(chord.labels.joined())"
                )
                fromTable.insert(EditorShortcuts.Binding(
                    modifiers: modifiers(chord), keyCode: chord.key.keyCode, action: action
                ))
            }
        }
        // 편집기가 듣는 키 가운데 표에 없는 것도 없다.
        #expect(fromTable == Set(EditorShortcuts.bindings))
        #expect(EditorShortcuts.bindings.count == fromTable.count)
    }

    /// "마크다운으로 입력"의 줄 머리 기호는 편집기가 줄 맨 앞에서 Space와 함께 받는 기호와 같다(D-044).
    @Test func lineMarkersInTheTableAreTheEditorsSpaceTriggers() throws {
        let expected: [String: [LineKind]] = [
            "제목 1, 2, 3": [.heading(1), .heading(2), .heading(3)],
            "글머리표": [.bullet],
            "투두": [.todo(done: false), .todo(done: false)],
            "토글": [.toggle],
            "제목 토글 (토글 줄에서)": [.toggleHeading(1), .toggleHeading(2), .toggleHeading(3)],
            "인용문": [.quote, .quote],
        ]
        let rows = ShortcutTable.standard.entries(in: .markdownInput).filter { expected[$0.action] != nil }
        #expect(Set(rows.map(\.action)) == Set(expected.keys))
        for row in rows {
            let kinds = try #require(expected[row.action])
            #expect(row.keyLabels.count == kinds.count, "\(row.action)")
            for (label, kind) in zip(row.keyLabels, kinds) {
                let source = row.action == "제목 토글 (토글 줄에서)" ? "+ " + label : label
                let doc = MarkdownDocument(source)
                // [ ] 표기는 닫는 괄호까지 입력하면 이미 투두로 파싱된다.
                if label == "[ ]" {
                    #expect(doc.lines[0].kind == kind)
                    continue
                }
                let edit = try #require(
                    EditorCommands.spaceTrigger(doc, selection: NSRange(location: doc.length, length: 0)),
                    "\(row.action) \(label)"
                )
                #expect(MarkdownDocument(edit.applied(to: source)).lines[0].kind == kind, "\(row.action) \(label)")
            }
        }
    }
}
