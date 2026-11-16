import AppKit
import Editor
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
            let isAppRow = entry.group == .global || entry.group == .noteWindow
            #expect((entry.command != nil) == isAppRow, "\(entry.action)")
        }
        #expect(table.entries(in: .global).allSatisfy { $0.chords.first?.modifiers == [.control, .option] })
        // ⌃⌥Space는 쓰지 않는다(입력 소스 전환과 겹침, spec 13).
        #expect(!table.entries.contains { $0.chords.contains(KeyChord(.space, [.control, .option])) })
    }

    /// 같은 곳에서 듣는 키가 겹치지 않는다: App이 받는 것끼리, 그리고 편집기가 먼저 받는 "편집" 줄과.
    @Test func chordsDoNotCollideWithinTheNoteWindow() {
        let table = ShortcutTable.standard
        let heard = (table.entries(in: .global) + table.entries(in: .noteWindow) + table.entries(in: .editing))
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
}
