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
        "- [ ] 투두\n\t- 탭 들여쓰기  \n+ 토글\n> 인용문\n==형광펜=={3} ~~취소~~ `코드`\n```swift\nlet a = 1\n```\n",
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

    @Test(arguments: ["---", "---\n첫 문단", "---\n첫 문단\n---\n둘째 문단"])
    func headerlessDividersStayInTheBody(_ source: String) {
        let decoded = NoteFileCodec.decode(source)
        #expect(decoded.body == source)
        #expect(NoteFileCodec.decode(NoteFileCodec.encode(decoded, over: source)).body == source)
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

    @Test func readsFractionalAndDateOnlyDates() throws {
        #expect(NoteFileCodec.parseDate("2026-11-16T12:08:00Z") == Date(timeIntervalSince1970: 1_794_830_880))
        let fractional = try #require(NoteFileCodec.parseDate("2026-11-16T12:08:00.123Z"))
        #expect(abs(fractional.timeIntervalSince1970 - 1_794_830_880.123) < 0.0005)
        #expect(NoteFileCodec.parseDate("2026-11-16T21:08:00+09:00") == Date(timeIntervalSince1970: 1_794_830_880))
        #expect(NoteFileCodec.parseDate("2026-11-17") == Date(timeIntervalSince1970: 1_794_873_600))
        #expect(NoteFileCodec.parseDate("2026-11-17 09:00") == nil)
        #expect(NoteFileCodec.parseDate("내일") == nil)
    }

    /// 고쳐 쓸 때 값이 그대로인 줄은 원래 표기 그대로 남는다.
    @Test func rewritingKeepsLinesWhoseValueDidNotChange() {
        let text = "---\ncreated: 2026-11-16T12:08:00.123Z\ntags: [a]\ntitle: 손으로 쓴 제목\n"
            + "reminder: 2026-11-17 09:00\n---\n본문"
        var content = NoteFileCodec.decode(text)
        #expect(content.reminder == nil)
        #expect(content.unknownLines == ["tags: [a]"])
        #expect(NoteFileCodec.encode(content, over: text) == text)

        content.body = "고친 본문"
        content.colorID = PaletteID(rawValue: "tint-2")
        #expect(NoteFileCodec.encode(content, over: text)
            == "---\ncreated: 2026-11-16T12:08:00.123Z\ntags: [a]\ntitle: 손으로 쓴 제목\n"
            + "reminder: 2026-11-17 09:00\ncolor: tint-2\n---\n고친 본문")

        content.title = "새 제목"
        content.reminder = Date(timeIntervalSince1970: 1_800_000_000)
        content.colorID = nil
        #expect(NoteFileCodec.encode(content, over: text)
            == "---\ncreated: 2026-11-16T12:08:00.123Z\ntags: [a]\ntitle: \"새 제목\"\n"
            + "reminder: 2027-01-15T08:00:00Z\n---\n고친 본문")
    }

    @Test func rewritingKeepsLineEndingsAndMissingFinalNewline() {
        let windows = "---\r\ntitle: 윈도\r\ntags: [a]\r\n---\r\n본문\r\n"
        #expect(NoteFileCodec.encode(NoteFileCodec.decode(windows), over: windows) == windows)
        let unterminated = "---\ntitle: \"t\"\n---"
        #expect(NoteFileCodec.encode(NoteFileCodec.decode(unterminated), over: unterminated) == unterminated)
        // 머리가 없던 파일은 새 파일의 표기로 쓴다.
        let content = NoteFileContent(title: "t", body: "# 그냥 마크다운")
        #expect(NoteFileCodec.encode(content, over: "# 그냥 마크다운") == NoteFileCodec.encode(content))
    }

    /// 들여쓴 줄은 아는 키처럼 보여도 최상위 항목이 아니다.
    @Test func indentedLinesAreNotTopLevelKeys() {
        let text = "---\ntitle: real\nmeta:\n  title: inner\n\tcolor: tint-9\n---\n본문"
        var content = NoteFileCodec.decode(text)
        #expect(content.title == "real")
        #expect(content.colorID == nil)
        #expect(content.unknownLines == ["meta:", "  title: inner", "\tcolor: tint-9"])

        content.body = "고친 본문"
        #expect(NoteFileCodec.encode(content, over: text)
            == "---\ntitle: real\nmeta:\n  title: inner\n\tcolor: tint-9\n---\n고친 본문")
    }

    @Test func byteOrderMarkBeforeTheHeaderIsSkippedAndKept() {
        let text = "\u{FEFF}---\ntitle: bom\n---\n본문"
        var content = NoteFileCodec.decode(text)
        #expect(content.title == "bom")
        #expect(content.body == "본문")
        content.body = "고친 본문"
        #expect(NoteFileCodec.encode(content, over: text) == "\u{FEFF}---\ntitle: bom\n---\n고친 본문")
    }
}
