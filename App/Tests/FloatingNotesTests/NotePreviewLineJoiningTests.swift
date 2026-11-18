import Foundation
import Models
import Testing
@testable import Browse
@testable import Library

@Suite struct NotePreviewLineJoiningTests {
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
