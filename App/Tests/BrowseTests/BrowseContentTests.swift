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
            notes: notes, floating: floating, query: BrowseQuery(query, isComposing: composing),
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

    @Test func floatingNotesComeFirstThenRecentOnes() {
        #expect(content().entries.map(\.label) == [
            "# 떠 있는 노트", "today", "home", "scratch",
            "# 최근에 연 노트", "release", "untitled", "meeting", "api",
            "---", "library",
        ])
    }

    /// 떠 있는 노트는 앞에 있는 창부터, 최근에 연 노트는 받은 차례(최근에 고친 것이 앞) 그대로다.
    @Test func floatingOrderFollowsTheWindowOrder() {
        let floating = ["scratch", "today"].map(NoteID.init(rawValue:))
        #expect(content(floating: floating).entries.map(\.label) == [
            "# 떠 있는 노트", "scratch", "today",
            "# 최근에 연 노트", "home", "release", "untitled", "meeting", "api",
            "---", "library",
        ])
        // 노트가 없어진 창 상태는 건너뛴다.
        let stale = ["gone", "today"].map(NoteID.init(rawValue:))
        #expect(content(floating: stale).entries.prefix(3).map(\.label) == ["# 떠 있는 노트", "today", "# 최근에 연 노트"])
    }

    /// "최근에 연 노트"는 마지막으로 연 때가 가까운 것이 앞이다(D-033). 연 때를 적은 적이 없는 노트는
    /// 고친 시각으로 견주고, 때가 같으면 받은 차례를 지킨다.
    @Test func recentNotesAreOrderedByWhenTheyWereLastOpened() {
        func note(_ id: String, modifiedMinutesAgo minutes: Double) -> BrowseIndexedNote {
            BrowseIndexedNote(Note(
                id: NoteID(rawValue: id), title: id, body: "", created: TestClock.now,
                modified: TestClock.now.addingTimeInterval(-minutes * 60)
            ))
        }
        // 받은 차례는 최근에 고친 것이 앞이다.
        let notes = [
            note("edited-now", modifiedMinutesAgo: 0), note("edited-10m", modifiedMinutesAgo: 10),
            note("edited-1h", modifiedMinutesAgo: 60), note("edited-1d", modifiedMinutesAgo: 1440),
        ]
        func labels(_ opened: [String: Double]) -> [String] {
            let times = Dictionary(uniqueKeysWithValues: opened.map {
                (NoteID(rawValue: $0.key), TestClock.now.addingTimeInterval(-$0.value * 60))
            })
            return BrowseContent(
                notes: notes, floating: [], lastOpened: times, query: BrowseQuery("", isComposing: false),
                excluding: nil
            ).entries.compactMap { entry in
                if case .note(let row) = entry { row.id.rawValue } else { nil }
            }
        }

        // 적힌 것이 없으면 고친 차례 그대로다.
        #expect(labels([:]) == ["edited-now", "edited-10m", "edited-1h", "edited-1d"])
        // 오래전에 고쳤어도 방금 연 노트가 맨 앞이고, 방금 고쳤어도 연 지 오래된 노트는 뒤로 간다.
        #expect(labels(["edited-1d": 1, "edited-now": 120]) == ["edited-1d", "edited-10m", "edited-1h", "edited-now"])
        // 연 적이 없는 노트는 고친 시각으로 그 사이에 낀다.
        #expect(labels(["edited-1h": 5, "edited-1d": 30]) == ["edited-now", "edited-1h", "edited-10m", "edited-1d"])
    }

    /// 떠 있는 노트의 차례와 검색 결과의 차례는 연 때를 따르지 않는다.
    @Test func lastOpenedTimesOnlyOrderTheRecentSection() {
        let later = TestClock.now.addingTimeInterval(60)
        let times = [NoteID(rawValue: "api"): later, NoteID(rawValue: "scratch"): later]
        let sections = BrowseContent(
            notes: Sample.notes, floating: Sample.floating, lastOpened: times,
            query: BrowseQuery("", isComposing: false), excluding: nil
        )
        #expect(sections.entries.map(\.label) == [
            "# 떠 있는 노트", "today", "home", "scratch",
            "# 최근에 연 노트", "api", "release", "untitled", "meeting",
            "---", "library",
        ])
        let unordered = content("배포").entries.map(\.label)
        let ordered = BrowseContent(
            notes: Sample.notes, floating: Sample.floating, lastOpened: times,
            query: BrowseQuery("배포", isComposing: false), excluding: nil
        ).entries.map(\.label)
        #expect(ordered == unordered)
    }

    @Test func emptySectionsHaveNoHeader() {
        #expect(content(floating: []).entries.map(\.label) == [
            "# 최근에 연 노트", "today", "home", "scratch", "release", "untitled", "meeting", "api",
            "---", "library",
        ])
        let onlyFloating = Array(Sample.notes.prefix(2))
        #expect(content(notes: onlyFloating).entries.map(\.label) == ["# 떠 있는 노트", "today", "home", "---", "library"])
        // 노트가 하나도 없으면 라이브러리 열기만 남는다. 안내 문장도 구분선도 없다.
        #expect(content(notes: [], floating: []).entries == [.library])
    }

    /// 최근에 연 노트는 여덟 줄까지만 보인다(spec 16). 떠 있는 노트에는 한도가 없다.
    @Test func recentNotesAreLimitedToEight() {
        let many = (1...12).map { Sample.note("n\($0)", title: "노트 \($0)") }
        let floating = (1...2).map { NoteID(rawValue: "n\($0)") }
        let labels = content(notes: many, floating: floating).entries.map(\.label)
        #expect(labels == ["# 떠 있는 노트", "n1", "n2", "# 최근에 연 노트"]
            + (3...10).map { "n\($0)" } + ["---", "library"])
        // 찾을 때는 한도가 없다.
        #expect(content("노트", notes: many, floating: floating).entries.count == 12 + 3)
    }

    @Test func currentNoteIsExcluded() {
        #expect(content(excluding: "today").entries.map(\.label) == [
            "# 떠 있는 노트", "home", "scratch",
            "# 최근에 연 노트", "release", "untitled", "meeting", "api",
            "---", "library",
        ])
        #expect(content(excluding: "release").entries.map(\.label).contains("release") == false)
        // 찾을 때도 빠진다.
        #expect(content("배포", excluding: "today").entries.map(\.label) == ["release", "+ 배포", "---", "library"])
        // 떠 있는 노트가 지금 노트뿐이면 그 구획은 없다.
        let onlyCurrent = [NoteID(rawValue: "today")]
        #expect(content(floating: onlyCurrent, excluding: "today").entries.first?.label == "# 최근에 연 노트")
    }

    @Test func rowCarriesWhatTheLineShows() throws {
        let rows = content()
        let today = try #require(row("today", in: rows))
        #expect(today.title == "오늘 할 일")
        #expect(today.preview == "PR #482 리뷰, 배포 체크리스트 확인")
        #expect(today.previewHighlight == nil)
        #expect(today.isFloating)
        #expect(today.spaceID == Sample.work)
        #expect(today.reminder == TestClock.date(11, 16, 14, 12))
        let home = try #require(row("home", in: rows))
        #expect(home.colorID == PaletteID(rawValue: "tint-5"))
        let untitled = try #require(row("untitled", in: rows))
        #expect(untitled.title.isEmpty)
        #expect(untitled.preview == "주말 장보기 목록")
        #expect(!untitled.isFloating)
    }

    // MARK: - 찾는 중

    /// 구획 이름이 사라지고, 본문에서 맞은 줄은 맞은 자리부터 보이며 그 낱말이 굵게 표시된다.
    @Test func searchFindsInBodiesAndHighlightsTheMatch() throws {
        let found = content("배포")
        #expect(found.entries.map(\.label) == ["today", "release", "+ 배포", "---", "library"])
        let today = try #require(row("today", in: found))
        #expect(today.preview == "배포 체크리스트 확인")
        #expect(today.previewHighlight == 0..<2)
        #expect(today.isFloating)
        let release = try #require(row("release", in: found))
        #expect(release.preview == "배포 순서 확인")
        #expect(release.previewHighlight == 0..<2)
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
        #expect(titleOnly.preview == "디자인 싱크")
        #expect(titleOnly.previewHighlight == nil)
        let both = try #require(row("both", in: found))
        #expect(both.preview == "회의 안건")
        #expect(both.previewHighlight == 0..<2)
    }

    @Test func searchIsCaseInsensitiveAndHandlesDecomposedHangul() throws {
        let english = content("retry")
        #expect(english.entries.map(\.label) == ["api", "+ retry", "---", "library"])
        // 굵게 표시하는 `**`는 본문 첫머리에서 빠진다.
        #expect(try #require(row("api", in: english)).preview == "Retry policy")
        #expect(content("API").entries.first?.label == "api")
        #expect(content("api notes").entries.first?.label == "api")

        let decomposed = [Sample.note(
            "nfd", title: "회의록".decomposedStringWithCanonicalMapping,
            body: "배포 순서".decomposedStringWithCanonicalMapping
        )]
        #expect(content("회의", notes: decomposed, floating: []).entries.first?.label == "nfd")
        let inBody = try #require(row("nfd", in: content("순서", notes: decomposed, floating: [])))
        #expect(inBody.preview.precomposedStringWithCanonicalMapping == "순서")
        #expect(inBody.previewHighlight == 0..<2)
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
        #expect(content("   ").entries.first == .header(BrowseContent.floatingTitle))
    }

    // MARK: - 본문 첫머리

    @Test(arguments: [
        ("[ ] 치과 예약 전화\n[x] 택배 반품 신청\n", "치과 예약 전화, 택배 반품 신청"),
        ("- [ ] 표준 투두\n- 글머리표\n* 별표\n", "표준 투두, 글머리표, 별표"),
        ("# 제목\n## 작은 제목\n본문\n", "제목, 작은 제목, 본문"),
        ("> 토글\n\t- 안쪽 줄\n\t\t[ ] 더 안쪽\n", "토글, 안쪽 줄, 더 안쪽"),
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
}
