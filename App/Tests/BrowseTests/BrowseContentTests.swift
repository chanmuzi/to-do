import Foundation
import Models
import Routing
import Testing
@testable import Browse

/// 목록의 내용과 차례, 걸러 내기, 지금 노트 빼기(spec 8).
@Suite struct BrowseContentTests {
    private func content(
        _ query: String = "", composing: Bool = false, notes: [BrowseIndexedNote] = Sample.notes,
        floating: [NoteID] = Sample.floating, excluding: String? = nil
    ) -> BrowseContent {
        BrowseContent(
            notes: notes, floating: floating, lastOpened: Dictionary(uniqueKeysWithValues: notes.map { ($0.note.id, TestClock.now) }), query: BrowseQuery(query, isComposing: composing),
            excluding: excluding.map(NoteID.init(rawValue:))
        )
    }

    private func row(_ id: String, in content: BrowseContent) -> BrowseNoteRow? {
        content.entries.lazy.compactMap { entry -> BrowseNoteRow? in
            if case .note(let row) = entry, row.id.rawValue == id { return row }
            return nil
        }.first
    }

    // MARK: - 글자를 치기 전

    @Test func recentRequiresFocusAndExcludesArchivedAndCurrent() {
        var archived = Sample.notes[1].note
        archived.isArchived = true
        let notes = Sample.notes
        let times = Dictionary(uniqueKeysWithValues: notes.prefix(4).enumerated().map {
            ($0.element.note.id, TestClock.now.addingTimeInterval(Double($0.offset)))
        })
        let recent = BrowseContent(notes: [notes[0], BrowseIndexedNote(archived)] + notes.dropFirst(2),
                                   floating: Sample.floating, lastOpened: times, query: BrowseQuery(""),
                                   excluding: notes[2].note.id)
        #expect(recent.entries.map(\.label) == ["# 최근", "release", "today", "---", "library"])
        #expect(row("today", in: recent)?.isFloating == true)
        #expect(row("today", in: recent)?.preview == "")
        #expect(BrowseContent(notes: notes, floating: [], query: BrowseQuery(""), excluding: nil).entries == [.library])
    }

    @Test func recentLimitIncludesPinnedRowsAndSearchIncludesEveryMatch() {
        let notes = (1...12).map { Sample.note("n\($0)", title: "노트") }
        let floating = notes.map(\.note.id)
        #expect(content(notes: notes, floating: floating).entries.count == 8 + 3)
        #expect(content("노트", notes: notes, floating: floating).entries.count == 12 + 3)
    }

    @Test func archivedMatchesFollowActiveAndFocusOrdersEachGroup() {
        var archived = Sample.note("archive", title: "회의").note
        archived.isArchived = true
        let notes = [BrowseIndexedNote(archived), Sample.note("first", title: "회의"),
                     Sample.note("second", title: "회의"), Sample.note("body", title: "", body: "오늘 회의 준비")]
        let results = BrowseContent(notes: notes, floating: [], lastOpened: [notes[2].note.id: TestClock.now],
                                    query: BrowseQuery("회의"), excluding: nil)
        #expect(results.entries.map(\.label) == ["second", "first", "body", "archive", "+ 회의", "---", "library"])
    }

    // MARK: - 찾는 중

    /// 구획 이름이 사라지고, 본문에서 맞은 줄은 맞은 자리부터 보이며 그 낱말이 굵게 표시된다.
    @Test func searchFindsInBodiesAndHighlightsTheMatch() throws {
        let found = content("배포")
        #expect(found.entries.map(\.label) == ["today", "release", "+ 배포", "---", "library"])
        let today = try #require(row("today", in: found))
        #expect(today.preview.contains("리뷰, 배포"))
        #expect(today.previewHighlight == 10..<12)
        #expect(today.isFloating)
        let release = try #require(row("release", in: found))
        #expect(release.preview.hasSuffix("배포 순서 확인"))
        #expect(release.previewHighlight == 8..<10)
    }

    /// 제목에서 맞은 노트가 먼저, 본문에서만 맞은 노트가 다음이다. 제목에서만 맞으면 본문 첫머리는 그대로다.
    @Test func titleMatchesComeBeforeBodyMatches() throws {
        let notes = [
            Sample.note("body-only", title: "장보기", body: "회의 간식 사기\n"),
            Sample.note("title-only", title: "회의 메모", body: "디자인 싱크\n"),
            Sample.note("both", title: "주간 회의", body: "다음 회의 안건\n"),
            Sample.note("neither", title: "스크래치", body: "아이디어\n"),
        ]
        let found = content("회의", notes: notes, floating: [])
        #expect(found.entries.map(\.label) == ["title-only", "both", "body-only", "+ 회의", "---", "library"])
        let titleOnly = try #require(row("title-only", in: found))
        #expect(titleOnly.preview.isEmpty && titleOnly.titleHighlight == 0..<2)
        #expect(titleOnly.previewHighlight == nil)
        let both = try #require(row("both", in: found))
        #expect(both.preview.isEmpty && both.titleHighlight == 3..<5)
        #expect(both.previewHighlight == nil)
    }

    @Test func searchIsCaseInsensitiveAndHandlesDecomposedHangul() throws {
        let english = content("retry")
        #expect(english.entries.map(\.label) == ["api", "+ retry", "---", "library"])
        // 굵게 표시하는 `**`는 본문 첫머리에서 빠진다.
        #expect(try #require(row("api", in: english)).preview.hasSuffix("Retry policy"))
        #expect(content("API").entries.first?.label == "api")
        #expect(content("api notes").entries.first?.label == "api")

        let decomposed = [Sample.note(
            "nfd", title: "회의록".decomposedStringWithCanonicalMapping,
            body: "배포 순서".decomposedStringWithCanonicalMapping
        )]
        #expect(content("회의", notes: decomposed, floating: []).entries.first?.label == "nfd")
        let inBody = try #require(row("nfd", in: content("순서", notes: decomposed, floating: [])))
        #expect(inBody.preview.precomposedStringWithCanonicalMapping == "배포 순서")
        #expect(inBody.previewHighlight == 3..<5)
    }

    /// 조합 중인 글자("뱊")로도 결과가 끊기지 않는다.
    @Test func compositionInProgressKeepsTheResults() {
        // "배"는 "배포"와 "택배"의 앞부분이다.
        #expect(content("배", composing: true).entries.map(\.label)
            == ["today", "home", "release", "+ 배", "---", "library"])
        #expect(content("뱊", composing: true).entries.map(\.label) == ["today", "release", "+ 뱊", "---", "library"])
        #expect(content("뱊", composing: false).entries.map(\.label) == ["+ 뱊", "---", "library"])
    }

    /// 맞는 노트가 없으면 새 노트 만들기만 남는다. 안내 문장은 없다.
    @Test func noMatchLeavesOnlyTheCreateRow() {
        #expect(content("xyz").entries == [.create(query: "xyz"), .separator, .library])
        #expect(content("  xyz ").entries.first == .create(query: "xyz"))
        // 공백뿐인 검색어는 찾지 않는 것과 같다.
        #expect(content("   ").entries.first == .header(BrowseContent.recentTitle))
    }

    @Test(arguments: [
        ("목요일에는 첫 번째 시안을 살펴보기", "목요일에는 첫 번째 시안을 살펴보기"),
        ("지난주,목요일에는 첫 번째 시안을 살펴보기", "…목요일에는 첫 번째 시안을 살펴보기"),
        ("이전,abcdefghijkl시안", "…abcdefghijkl시안"),
        ("길고긴공백없는하나의낱말뒤에는,,  다음 시안", "…다음 시안"),
        ("abcdefghijklmnop 다음 시안 확인", "…다음 시안 확인"),
        ("공백도쉼표도전혀없는아주긴낱말시안", "…시안"),
        ("👩🏽‍💻가 쓴 시안", "👩🏽‍💻가 쓴 시안"),
    ])
    func previewStartsAtAWordAndHighlightsTheOriginalMatch(body: String, expected: String) throws {
        let match = try #require(BrowseMatcher.firstMatch(of: BrowseQuery("시안"), in: body))
        let result = BrowsePreview.display(body, match: match)
        #expect(result.text == expected)
        let highlight = try #require(result.highlight)
        #expect(String(result.text.dropFirst(highlight.lowerBound).prefix(highlight.count)) == "시안")
    }

    // MARK: - 본문 첫머리

    @Test(arguments: [
        ("[ ] 치과 예약 전화\n[x] 택배 반품 신청\n", "치과 예약 전화, 택배 반품 신청"),
        ("- [ ] 표준 투두\n- 글머리표\n* 별표\n", "표준 투두, 글머리표, 별표"),
        ("# 제목\n## 작은 제목\n본문\n", "제목, 작은 제목, 본문"),
        ("+ 토글\n\t- 안쪽 줄\n\t\t[ ] 더 안쪽\n", "토글, 안쪽 줄, 더 안쪽"),
        ("> 인용문\n>   두 칸 뒤\n\t> 들여 쓴 인용문\n", "인용문, 두 칸 뒤, 들여 쓴 인용문"),
        ("\n\n  \n첫 줄\n\n둘째 줄\n", "첫 줄, 둘째 줄"),
        ("**굵게** ~~취소~~ ==형광== ==회색=={2} `코드`\n", "굵게 취소 형광 회색 코드"),
        ("```\nlet x = 1\n```\n", "let x = 1"),
        ("[링크](https://example.com) 보기\n", "링크 보기"),
        ("PR #482 리뷰\n", "PR #482 리뷰"),
        ("", ""),
    ])
    func previewFlattensTheBody(body: String, expected: String) {
        #expect(BrowsePreview.flatten(body) == expected)
    }

    /// "라이브러리 열기"를 두지 않을 때는 그 위의 구분선도 없다. 줄이 하나도 없으면 목록이 빈다.
    @Test func libraryRowAndItsSeparatorCanBeLeftOut() {
        let listed = BrowseContent(
            notes: Sample.notes, floating: Sample.floating, lastOpened: [Sample.notes.last!.note.id: TestClock.now], query: BrowseQuery(""), excluding: nil,
            showsLibrary: false
        ).entries
        #expect(listed.last?.label == "api")
        #expect(!listed.contains(.library))
        #expect(!listed.contains(.separator))

        let searching = BrowseContent(
            notes: Sample.notes, floating: Sample.floating, query: BrowseQuery("없는 말"), excluding: nil,
            showsLibrary: false
        ).entries
        #expect(searching.map(\.label) == ["+ 없는 말"])

        let empty = BrowseContent(
            notes: [], floating: [], query: BrowseQuery(""), excluding: nil, showsLibrary: false
        ).entries
        #expect(empty.isEmpty)
    }
}
