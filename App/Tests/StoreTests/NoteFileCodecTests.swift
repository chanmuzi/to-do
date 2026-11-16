import Foundation
import Testing
import Models
@testable import Store

@Suite struct NoteFileCodecTests {
    @Test(arguments: [
        "",
        "한 줄",
        "\n\n앞뒤 빈 줄\n\n",
        "끝에 줄바꿈 없음",
        "---\n본문이 구분선으로 시작\n---\n",
        "- [ ] 투두\n\t- 탭 들여쓰기  \n> 토글\n==형광펜=={3} ~~취소~~ `코드`\n```swift\nlet a = 1\n```\n",
        "윈도 줄바꿈\r\n두 번째 줄\r\n",
        "이모지 👩‍💻 와 결합 문자 e\u{301}",
        "title: 본문 안의 머리 흉내\ncreated: 아님",
    ])
    func bodyRoundTripsExactly(body: String) {
        let content = NoteFileContent(
            title: "제목", spaceID: SpaceID(rawValue: "work"), colorID: PaletteID(rawValue: "tint-3"),
            reminder: Date(timeIntervalSince1970: 1_800_000_000),
            created: Date(timeIntervalSince1970: 1_790_000_000), body: body
        )
        let decoded = NoteFileCodec.decode(NoteFileCodec.encode(content))
        #expect(decoded == content)
        #expect(Array(decoded.body.utf8) == Array(body.utf8))
    }

    @Test(arguments: ["", "보통 제목", "따옴표 \"안\" 과 역슬래시 \\", "콜론: 있는 제목", "  앞뒤 공백  ", "# 샵", "---"])
    func titleRoundTrips(title: String) {
        let decoded = NoteFileCodec.decode(NoteFileCodec.encode(NoteFileContent(title: title, body: "본문")))
        #expect(decoded.title == title)
        #expect(decoded.body == "본문")
    }

    @Test func writesTheDocumentedFormat() {
        let text = NoteFileCodec.encode(NoteFileContent(
            title: "회의 메모", spaceID: SpaceID(rawValue: "work"), colorID: PaletteID(rawValue: "tint-3"),
            reminder: Date(timeIntervalSince1970: 1_800_000_000),
            created: Date(timeIntervalSince1970: 1_790_000_000), body: "- [ ] 할 일\n"
        ))
        #expect(text == """
        ---
        title: "회의 메모"
        space: "work"
        color: tint-3
        reminder: 2027-01-15T08:00:00Z
        created: 2026-09-21T14:13:20Z
        ---
        - [ ] 할 일

        """)
    }

    @Test func omitsEmptyFields() {
        let text = NoteFileCodec.encode(NoteFileContent(title: "", body: "x"))
        #expect(text == "---\ntitle: \"\"\n---\nx")
    }

    @Test func readsFilesWithoutFrontmatterAsBody() {
        let text = "# 그냥 마크다운\n내용\n"
        #expect(NoteFileCodec.decode(text) == NoteFileContent(body: text))
        // 닫는 구분선이 없으면 머리로 보지 않는다.
        let unclosed = "---\ntitle: x\n본문"
        #expect(NoteFileCodec.decode(unclosed) == NoteFileContent(body: unclosed))
    }

    @Test func readsHandWrittenFrontmatterAndKeepsUnknownLines() {
        let text = "---\r\ntitle: 따옴표 없는 제목\r\ntags: [a, b]\r\ncolor: tint-1\r\n---\r\n본문\r\n"
        let decoded = NoteFileCodec.decode(text)
        #expect(decoded.title == "따옴표 없는 제목")
        #expect(decoded.colorID == PaletteID(rawValue: "tint-1"))
        #expect(decoded.unknownLines == ["tags: [a, b]"])
        #expect(decoded.body == "본문\r\n")
        #expect(NoteFileCodec.encode(decoded).contains("\ntags: [a, b]\n"))
    }

    @Test func frontmatterEndingAtEndOfFileHasEmptyBody() {
        #expect(NoteFileCodec.decode("---\ntitle: \"t\"\n---") == NoteFileContent(title: "t", body: ""))
    }
}
