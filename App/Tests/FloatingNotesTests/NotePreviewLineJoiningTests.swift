import Foundation
import Models
import Testing
@testable import Browse
@testable import Library

@Suite struct NotePreviewLineJoiningTests {
    @Test func hardBreakIsHiddenInSearchPreviewAndDerivedTitle() {
        let body = "- [ ] 첫 줄\\\n다음 줄"
        #expect(LibraryPreview(title: "", markdown: body).title == "첫 줄")
        #expect(NotePreviewText.firstLine(in: body) == "첫 줄")
        #expect(BrowsePreview.flatten(body) == "첫 줄, 다음 줄")
    }

    @Test func toggleHeadingProvidesTheUntitledNotesDisplayTitle() {
        let body = "+ ### **제목**\n\t- 항목"
        #expect(LibraryPreview(title: "", markdown: body).title == "제목")
        #expect(BrowsePreview.flatten(body) == "제목, 항목")
        #expect(NotePreviewText.firstLine(in: body) == "제목")
    }

    @Test(arguments: [
        ("정리했습니다.  \n\n- [ ] 창 크기 확인\n다음 항목", "정리했습니다. 창 크기 확인, 다음 항목"),
        ("기록한다.\n작업실에서", "기록한다. 작업실에서"),
        ("질문?\n네!\n목록:\n첫째,\n둘째", "질문? 네! 목록: 첫째, 둘째"),
        ("**끝。**\r\n다음", "끝。 다음"),
        ("\n  \n", ""),
    ])
    func libraryAndBrowseJoinVisibleLines(body: String, expected: String) {
        let note = Note(id: .make(), title: "작업", body: body, created: .now, modified: .now)
        #expect(LibraryPreview(note).subtitle == expected)
        #expect(BrowsePreview.flatten(body) == expected)
    }
}
