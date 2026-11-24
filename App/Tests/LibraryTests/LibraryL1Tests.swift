import AppKit
import Foundation
import Testing
import Models
import Store
import Theme
@testable import Library

@Suite(.serialized) @MainActor struct LibraryL1Tests {
    @Test func oldUnassignedSelectionDecodesAndOpensAll() throws {
        let f = try LibraryInteractionTests.Fixture(); defer { try? f.close() }
        var saved = LibraryPreferences(); saved.lastSelection = .space(nil)
        let decoded = try JSONDecoder().decode(LibraryPreferences.self, from: JSONEncoder().encode(saved))
        #expect(decoded.lastSelection == .space(nil))
        f.model.changeSettings { $0 = decoded }; f.model.opened()
        #expect(f.model.selection == .all)
        f.model.changeSettings { prefs in
            for view in LibrarySelection.views { prefs.setVisible(view, false) }
            prefs.opensLastSelection = false
        }
        f.model.opened()
        #expect(f.model.selection == .all)
        _ = try f.notes.create(NoteDraft(title: "소속 없음")); f.model.refresh()
        #expect(f.model.rows.count == 1)
    }
    @Test func inlineSpaceCreateRenameCancelAndBlank() throws {
        let f = try LibraryInteractionTests.Fixture(); defer { try? f.close() }
        f.model.beginSpaceEditing(); f.model.spaceName = "  "; f.model.submitSpaceEditing()
        #expect(f.model.spaceList.isEmpty && f.model.editingSpace)
        f.model.setIcon(.emoji("📁"), for: nil)
        #expect(f.model.spaces.spaces.isEmpty)
        f.model.spaceName = " 업무 "; f.model.submitSpaceEditing()
        let space = try #require(f.model.spaceList.first)
        #expect(space.name == "업무" && space.icon == .emoji("📁") && !f.model.editingSpace)
        f.model.beginSpaceEditing(space.id); f.model.spaceName = "취소"; f.model.cancelSpaceEditing()
        #expect(f.model.spaceList[0].name == "업무")
        f.model.beginSpaceEditing(space.id); f.model.spaceName = "개인"; f.model.submitSpaceEditing()
        #expect(f.model.spaceList[0].name == "개인" && f.model.spaceList[0].id == space.id)
    }
    @Test func untitledUsesBodyFirstLineAndDoesNotRepeatItOrTodoProgress() {
        let note = Note(id: .make(), body: "첫 줄\n둘째 줄\n[ ] 할 일", created: Date(), modified: Date())
        #expect(LibraryPreview(note).title == "첫 줄")
        #expect(LibraryPreview(note).subtitle == "둘째 줄, 할 일")
        var one = note; one.body = "[ ] 할 일"
        #expect(LibraryPreview(one).title == "할 일" && LibraryPreview(one).subtitle.isEmpty)
        one.body = ""; #expect(LibraryPreview(one).title == "제목 없음" && LibraryPreview(one).isEmpty)
        #expect(LibraryPreview(one).upcomingTitle(for: ScheduleItem(start: Date())) == "리마인더")
        one.title = "제목"; one.body = "[ ] "
        #expect(LibraryPreview(one).subtitle.isEmpty)
        one.body = "[ ] 남음\n- [x] 끝\n  [x]  \t\n[ ] "
        #expect(LibraryPreview(one).total == 2 && LibraryPreview(one).completed == 1)
    }
    @Test func previewUsesEditorMarkersAndPreservesCodeAndLiteralSymbols() {
        let body = "# **제목** `글자`\n- [x] [링크](https://example.org) ==강조==\n```swift\n**그대로**\n```"
        let note = Note(id: .make(), body: body, created: Date(), modified: Date())
        #expect(LibraryPreview(note).title == "제목 글자")
        #expect(LibraryPreview(note).subtitle == "링크 강조, **그대로**")
    }

    @Test func trashOmitsTheHeaderCreationAction() throws {
        let f = try LibraryInteractionTests.Fixture(); defer { try? f.close() }
        f.model.select(.trash)
        #expect(!f.model.showsNewNote)
        f.model.select(.all)
        #expect(f.model.showsNewNote)
    }
    @Test func sidebarAndRightInfoRenderWithoutRemovedControls() throws {
        let f = try LibraryInteractionTests.Fixture(); defer { try? f.close() }
        _ = try f.notes.create(NoteDraft(body: "제목 대신 첫 줄\n보조 줄", reminder: Date().addingTimeInterval(3600)))
        f.coordinator.allowsKeyWindows = false; f.coordinator.show()
        RunLoop.main.run(until: Date().addingTimeInterval(0.08))
        let root = try #require(f.coordinator.window?.contentView)
        root.layoutSubtreeIfNeeded()
        let rows = LibraryInteractionTests().descendants(root).compactMap { $0 as? LibraryRowInputView }
        #expect(rows.contains { $0.accessibilityLabel() == "제목 대신 첫 줄" })
        #expect(f.model.theme.component(.librarySidebarRowGap) == 2)
        #expect(f.model.theme.component(.libraryRowPaddingY) == 9)
        f.model.beginSpaceEditing()
        RunLoop.main.run(until: Date().addingTimeInterval(0.08))
        let field = try #require(LibraryInteractionTests().descendants(root).compactMap { $0 as? NSTextField }.first { $0.accessibilityLabel() == "스페이스 이름" })
        #expect(field.focusRingType == .none)
        try LibraryInteractionTests().click(try #require(f.coordinator.window), at: NSPoint(x: 500, y: 100))
        #expect(!f.model.editingSpace)
    }
}
