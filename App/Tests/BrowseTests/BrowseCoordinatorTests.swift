import AppKit
import Models
import Routing
import Store
import Testing
@_spi(Verification) @testable import Browse

/// 노트 찾기를 실제로 띄우고 입력 경로(`insertText`, `setMarkedText`, `doCommand(by:)`)로 움직여 본다.
/// 한 번에 하나씩 돈다(`.serialized`): 창을 띄우는 시험이 한꺼번에 시작하면 메인 액터가 밀려, 전환 시간을
/// 기다리는 다른 시험이 제때 차례를 받지 못한다.
@MainActor
@Suite(.serialized) struct BrowseCoordinatorTests {
    private let fixture: BrowseFixture
    private let browse: BrowseCoordinator
    private let ids: [String: NoteID]

    init() throws {
        fixture = try BrowseFixture()
        // 나중에 만든 것이 목록의 앞이다: api가 가장 오래됐고 today가 가장 최근이다.
        var ids: [String: NoteID] = [:]
        ids["api"] = try fixture.add("API Notes", body: "Rate limit and Retry policy\n", space: Sample.work)
        ids["untitled"] = try fixture.add("", body: "주말 장보기 목록\n", space: Sample.home)
        ids["release"] = try fixture.add(
            "릴리즈 노트 초안", body: "2.3 변경 사항 정리\n- 배포 순서 확인\n", space: Sample.work,
            reminder: TestClock.date(11, 17, 10, 0)
        )
        ids["home"] = try fixture.add("개인", body: "[ ] 치과 예약 전화\n", space: Sample.home, floating: true)
        ids["today"] = try fixture.add(
            "오늘 할 일", body: "[ ] PR #482 리뷰\n[ ] 배포 체크리스트 확인\n", space: Sample.work,
            reminder: TestClock.date(11, 16, 14, 12), floating: true
        )
        self.ids = ids
        browse = fixture.makeCoordinator()
    }

    private func panelHeight(rows: Int, headers: Int) -> CGFloat {
        let theme = fixture.theme
        let style = BrowseStyle(theme: theme)
        return theme.component(.browsePadding) * 2 + theme.component(.browseFindHeight) + theme.component(.browseFindGap)
            + style.headerHeight * CGFloat(headers) + theme.component(.rowHeight) * CGFloat(rows) + style.separatorHeight
    }

    private func id(_ key: String) throws -> NoteID {
        try #require(ids[key])
    }

    private func input() throws -> NSTextView {
        try #require(browse.inputView)
    }

    private func press(_ selector: Selector) throws {
        try input().doCommand(by: selector)
    }

    private let returnKey = #selector(NSResponder.insertNewline(_:))
    private let downKey = #selector(NSResponder.moveDown(_:))
    private let upKey = #selector(NSResponder.moveUp(_:))
    private let escapeKey = #selector(NSResponder.cancelOperation(_:))

    /// 줄을 글로 적은 것에서 노트 id를 키로 바꿔 읽기 쉽게 한다.
    private var rows: [String] {
        browse.rowDescriptions.map { line in
            ids.reduce(line) { $0.replacingOccurrences(of: $1.value.rawValue, with: $1.key) }
        }
    }

    private var selectedRow: String? { rows.first { $0.hasPrefix("*") } }

    @Test func showsSectionsWithTheFirstRowSelected() throws {
        defer { fixture.cleanUp() }
        #expect(!browse.isVisible)
        browse.show(anchoredTo: nil, excluding: nil)
        #expect(browse.isVisible)
        let window = try #require(browse.window)
        #expect(window.frame.width == 300)
        #expect(window.canBecomeKey)
        #expect(window.firstResponder === browse.inputView)
        #expect(browse.showsPlaceholder)
        #expect(rows == [
            " header 떠 있는 노트",
            "*note today | 오늘 할 일 | PR #482 리뷰, 배포 체크리스트 확인 | 2:12 PM | pin",
            " note home | 개인 | 치과 예약 전화 | - | pin",
            " header 최근에 연 노트",
            " note release | 릴리즈 노트 초안 | 2.3 변경 사항 정리, 배포 순서 확인 | 내일 10:00 AM | -",
            " note untitled | 제목 없음 | 주말 장보기 목록 | - | -",
            " note api | API Notes | Rate limit and Retry policy | - | -",
            " separator",
            " library 라이브러리 열기",
        ])
        // 높이는 내용에 맞는다: 여백 6, 검색 칸 26, 틈 2, 구획 이름 24 둘, 줄 26 여섯, 구분선 13, 여백 6.
        let expectedHeight = panelHeight(rows: 6, headers: 2)
        #expect(window.frame.height == expectedHeight)
    }

    @Test func typingFiltersAndHighlightsWithoutSections() throws {
        defer { fixture.cleanUp() }
        browse.show(anchoredTo: nil, excluding: nil)
        let top = try #require(browse.window).frame.maxY
        try input().type("배포")
        #expect(!browse.showsPlaceholder)
        #expect(rows == [
            "*note today | 오늘 할 일 | 배포 체크리스트 확인 | 2:12 PM | pin",
            " note release | 릴리즈 노트 초안 | 배포 순서 확인 | 내일 10:00 AM | -",
            " create “배포” 새 노트 만들기",
            " separator",
            " library 라이브러리 열기",
        ])
        // 옛 줄은 바로 없어진다: 목록에는 지금 줄만 놓여 있고, 옛 모습과 겹쳐 넘기는 전환도 없다.
        #expect(browse.drawnRowCount == 5)
        #expect(browse.listTransitionCount == 0)
        // 대소문자를 가리지 않는다.
        try input().selectAll(nil)
        try input().type("RETRY")
        #expect(rows.first == "*note api | API Notes | Retry policy | - | -")
        #expect(browse.drawnRowCount == rows.count)
        #expect(browse.listTransitionCount == 0)
        // 맞는 노트가 없으면 새 노트 만들기만 남는다.
        try input().selectAll(nil)
        try input().type("xyz")
        #expect(rows == ["*create “xyz” 새 노트 만들기", " separator", " library 라이브러리 열기"])
        // 지우면 처음 목록으로 돌아온다.
        try input().selectAll(nil)
        try press(#selector(NSResponder.deleteBackward(_:)))
        #expect(rows.count == 9)
        #expect(browse.drawnRowCount == 9)
        #expect(browse.showsPlaceholder)
        // 높이가 바뀌어도 위쪽 가장자리는 그대로다.
        #expect(try #require(browse.window).frame.maxY == top)
    }

    /// 조합 중에도 걸러지고, 조합은 끊기지 않는다.
    @Test func filteringDuringCompositionKeepsTheComposition() throws {
        defer { fixture.cleanUp() }
        browse.show(anchoredTo: nil, excluding: nil)
        try input().compose("ㅂ")
        #expect(try input().hasMarkedText())
        // 낱자 "ㅂ"은 그 첫소리로 시작하는 글자("리뷰"의 "뷰")와 맞는다.
        #expect(rows.first == "*note today | 오늘 할 일 | 뷰, 배포 체크리스트 확인 | 2:12 PM | pin")
        try input().compose("배")
        #expect(try input().hasMarkedText())
        #expect(try input().string == "배")
        // 두벌식으로 "배포"를 치는 도중의 "뱊"에서도 결과가 그대로다.
        try input().compose("뱊")
        #expect(try input().hasMarkedText())
        #expect(try input().markedRange() == NSRange(location: 0, length: 1))
        #expect(rows.prefix(2).map { $0.split(separator: "|")[0] } == ["*note today ", " note release "])
        try input().compose("배포")
        #expect(try input().string == "배포")
        #expect(rows.count == 5)
    }

    private func useInputMethod(_ behavior: FakeInputContext.Behavior) throws {
        let view = try #require(browse.inputView as? BrowseTextView)
        view.inputContextOverride = FakeInputContext(textView: view, behavior: behavior)
    }

    /// 한글 두벌식: 마지막 글자가 조합 중일 때 ↵를 한 번 누르면, 입력기가 그 글자를 확정하고 같은 키 입력에서
    /// 줄바꿈 명령을 보낸다. 그 한 번으로 고른 줄이 열린다(↵를 두 번 누르게 하지 않는다).
    @Test func oneReturnOpensTheSelectedRowWithAKoreanInputMethod() throws {
        defer { fixture.cleanUp() }
        browse.show(anchoredTo: nil, excluding: nil)
        try useInputMethod(.commitsThenSendsNewline)
        try input().type("배")
        try input().compose("포")
        #expect(try input().hasMarkedText())
        #expect(rows.first?.hasPrefix("*note today") == true)

        try input().pressReturnKey()

        #expect(fixture.routes == [.openNote(try id("today"))])
        #expect(!browse.isVisible)
    }

    /// 일본어, 중국어 입력기: 조합 중의 ↵는 입력기가 후보를 확정하는 데 쓰고 명령을 보내지 않는다. 열지 않는다.
    @Test func returnConsumedByTheInputMethodDoesNotOpen() throws {
        defer { fixture.cleanUp() }
        browse.show(anchoredTo: nil, excluding: nil)
        try useInputMethod(.consumesReturnWhileComposing)
        try input().compose("API")
        try input().pressReturnKey()
        #expect(browse.isVisible)
        #expect(fixture.routes.isEmpty)
        #expect(try !input().hasMarkedText())
        #expect(try input().string == "API")

        try input().pressReturnKey()
        #expect(fixture.routes == [.openNote(try id("api"))])
        #expect(!browse.isVisible)
    }

    /// 줄바꿈 명령이 왔는데 조합 중인 글자가 남아 있으면 조합을 끝내기만 한다.
    @Test func newlineCommandWhileStillComposingOnlyEndsTheComposition() throws {
        defer { fixture.cleanUp() }
        browse.show(anchoredTo: nil, excluding: nil)
        try input().compose("배포")
        try press(returnKey)
        #expect(browse.isVisible)
        #expect(fixture.routes.isEmpty)
        #expect(try !input().hasMarkedText())
        #expect(try input().string == "배포")
    }

    /// 높이가 움직이는 중에 내용이 다시 바뀌어도 마지막 내용의 높이로 끝난다(조합을 끝낸 직후에 지우고 다시 칠 때).
    @Test func frameSettlesOnTheLastContentAfterQuickChanges() async throws {
        defer { fixture.cleanUp() }
        browse.show(anchoredTo: nil, excluding: nil)
        let window = try #require(browse.window)
        let top = window.frame.maxY
        try input().compose("배포")
        try press(returnKey)
        #expect(rows.count == 5)
        try input().selectAll(nil)
        try press(#selector(NSResponder.deleteBackward(_:)))
        #expect(rows.count == 9)
        try input().type("xyz")
        #expect(rows.count == 3)

        let deadline = Date().addingTimeInterval(3)
        while window.frame != browse.settledFrame, Date() < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        // 여백 6, 검색 칸 26, 틈 2, 새 노트 만들기 26, 구분선 13, 라이브러리 열기 26, 여백 6.
        let expectedHeight = panelHeight(rows: 2, headers: 0)
        #expect(window.frame.height == expectedHeight)
        #expect(window.frame.maxY == top)
    }

    @Test func arrowsMoveTheSelectionAndReturnOpensThatNote() throws {
        defer { fixture.cleanUp() }
        browse.show(anchoredTo: nil, excluding: nil)
        try press(downKey)
        #expect(selectedRow?.hasPrefix("*note home") == true)
        try press(downKey)
        #expect(selectedRow?.hasPrefix("*note release") == true)
        try press(upKey)
        try press(upKey)
        try press(upKey)
        #expect(selectedRow?.hasPrefix("*note today") == true)
        for _ in 0..<10 { try press(downKey) }
        #expect(selectedRow == "*library 라이브러리 열기")
        try press(upKey)
        try press(upKey)
        #expect(selectedRow?.hasPrefix("*note untitled") == true)

        try press(returnKey)
        #expect(fixture.routes == [.openNote(try id("untitled"))])
        #expect(!browse.isVisible)
    }

    @Test func filteredReturnOpensTheExpectedNote() throws {
        defer { fixture.cleanUp() }
        browse.show(anchoredTo: nil, excluding: nil)
        try input().type("배포")
        try press(downKey)
        try press(returnKey)
        #expect(fixture.routes == [.openNote(try id("release"))])
        #expect(!browse.isVisible)
    }

    @Test func createRowAndLibraryRowRoute() throws {
        defer { fixture.cleanUp() }
        let current = try id("today")
        browse.show(anchoredTo: nil, excluding: current)
        try input().type("새 계획")
        #expect(rows.first == "*create “새 계획” 새 노트 만들기")
        try press(returnKey)
        #expect(fixture.routes == [.newNote(NewNoteRequest(draft: NoteDraft(title: "새 계획"), nextTo: current))])
        #expect(!browse.isVisible)

        browse.show(anchoredTo: nil, excluding: current)
        #expect(try input().string.isEmpty)
        for _ in 0..<10 { try press(downKey) }
        try press(returnKey)
        #expect(fixture.routes.last == .openLibrary)
        #expect(!browse.isVisible)
        // 노트 찾기는 노트를 직접 만들거나 고치지 않는다.
        #expect(try fixture.notes.list().notes.count == 5)
    }

    @Test func currentNoteIsExcluded() throws {
        defer { fixture.cleanUp() }
        browse.show(anchoredTo: nil, excluding: try id("today"))
        #expect(rows.contains { $0.contains("note today") } == false)
        #expect(selectedRow?.hasPrefix("*note home") == true)
        try input().type("배포")
        #expect(rows.first?.hasPrefix("*note release") == true)
        #expect(rows.count == 4)
    }

    @Test func escapeClosesWithoutRouting() async throws {
        defer { fixture.cleanUp() }
        browse.show(anchoredTo: nil, excluding: nil)
        try input().type("배포")
        try press(escapeKey)
        #expect(!browse.isVisible)
        #expect(fixture.routes.isEmpty)
        let window = try #require(browse.window)
        let deadline = Date().addingTimeInterval(3)
        while window.isVisible, Date() < deadline { try await Task.sleep(for: .milliseconds(10)) }
        #expect(!window.isVisible)
        // 다시 열면 검색어가 비어 있다.
        browse.show(anchoredTo: nil, excluding: nil)
        #expect(try input().string.isEmpty)
        #expect(rows.count == 9)
    }

    @Test func anchorsUnderTheNoteWindowTopRow() throws {
        defer { fixture.cleanUp() }
        let screen = try #require(NSScreen.main)
        let visible = screen.visibleFrame
        let note = NSPanel(
            // 화면 위쪽에 둔다(아래로 목록 높이 한도만큼의 자리가 있다).
            contentRect: NSRect(x: visible.midX - 170, y: visible.maxY - 340, width: 340, height: 300),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true
        )
        browse.show(anchoredTo: note, excluding: nil)
        let frame = try #require(browse.window).frame
        // 위쪽은 상단 줄(28) 아래 2, 오른쪽은 노트 오른쪽 끝에서 24 안쪽.
        #expect(frame.maxY == note.frame.maxY - fixture.theme.shape(.chromeHeight) - fixture.theme.component(.browseAnchorGap))
        #expect(frame.maxX == note.frame.maxX - 24)
        #expect(frame.width == 300)
    }

    /// 저장소 변경은 다음 차례에 한꺼번에 읽힌다. 그때까지 기다린다.
    private func waitForReload(after count: Int) async throws {
        let deadline = Date().addingTimeInterval(3)
        while browse.listReadCount == count, Date() < deadline { try await Task.sleep(for: .milliseconds(5)) }
        #expect(browse.listReadCount == count + 1)
    }

    /// 열려 있는 동안 노트가 바뀌면 목록이 따라온다.
    @Test func listFollowsStoreChangesWhileOpen() async throws {
        defer { fixture.cleanUp() }
        browse.show(anchoredTo: nil, excluding: nil)
        try press(downKey)
        var reads = browse.listReadCount
        try fixture.notes.update(try id("api")) { $0.title = "API 메모" }
        try await waitForReload(after: reads)
        #expect(rows.contains { $0.contains("| API 메모 |") })
        // 고른 줄은 그대로다.
        #expect(selectedRow?.hasPrefix("*note home") == true)
        reads = browse.listReadCount
        try fixture.notes.moveToTrash(try id("home"))
        try await waitForReload(after: reads)
        #expect(rows.contains { $0.contains("note home") } == false)
    }

    /// 고른 노트의 제목, 본문, 리마인더가 바뀌어도 고른 줄은 그 노트를 따라간다(줄 전체가 아니라 노트 id로 견준다).
    @Test func selectionFollowsTheNoteWhenItsContentChanges() async throws {
        defer { fixture.cleanUp() }
        browse.show(anchoredTo: nil, excluding: nil)
        try press(downKey)
        try press(downKey)
        #expect(selectedRow?.hasPrefix("*note release") == true)
        let reads = browse.listReadCount
        try fixture.notes.update(try id("release")) {
            $0.title = "릴리즈 노트 2.3"
            $0.body = "고친 본문\n"
            $0.reminder = TestClock.date(11, 18, 9, 0)
        }
        try await waitForReload(after: reads)
        #expect(selectedRow?.hasPrefix("*note release | 릴리즈 노트 2.3 | 고친 본문 |") == true)
        // 그 줄에서 ↵를 누르면 그 노트가 열린다.
        try press(returnKey)
        #expect(fixture.routes == [.openNote(try id("release"))])
    }

    /// 변경이 잇달아 와도 노트 파일은 한 번만 다시 읽는다.
    @Test func burstOfStoreChangesReloadsOnce() async throws {
        defer { fixture.cleanUp() }
        browse.show(anchoredTo: nil, excluding: nil)
        let reads = browse.listReadCount
        #expect(reads == 1)
        try fixture.notes.update(try id("api")) { $0.title = "하나" }
        try fixture.notes.update(try id("release")) { $0.title = "둘" }
        try fixture.notes.update(try id("untitled")) { $0.title = "셋" }
        _ = try fixture.add("넷", body: "새 노트\n")
        // 바로는 읽지 않는다.
        #expect(browse.listReadCount == reads)
        try await waitForReload(after: reads)
        try await Task.sleep(for: .milliseconds(50))
        #expect(browse.listReadCount == reads + 1)
        #expect(rows.contains { $0.contains("| 하나 |") })
        #expect(rows.contains { $0.contains("| 둘 |") })
        #expect(rows.contains { $0.contains("| 셋 |") })
        #expect(rows.contains { $0.contains("| 넷 |") })
    }

    /// 닫힌 뒤에 온 변경으로는 다시 읽지 않는다.
    @Test func changesAfterClosingDoNotReload() async throws {
        defer { fixture.cleanUp() }
        browse.show(anchoredTo: nil, excluding: nil)
        try fixture.notes.update(try id("api")) { $0.title = "닫기 직전" }
        try press(escapeKey)
        let reads = browse.listReadCount
        try fixture.notes.update(try id("api")) { $0.title = "닫은 뒤" }
        try await Task.sleep(for: .milliseconds(50))
        #expect(browse.listReadCount == reads)
    }

    /// 노트 목록을 읽지 못해도 창은 쓸 수 있다: "라이브러리 열기"와 "새 노트 만들기"는 그대로 있고, 까닭은 기록으로 나간다.
    @Test func unreadableListStillShowsTheActionRowsAndReportsTheFailure() throws {
        defer { fixture.cleanUp(expectingLogs: true) }
        let store = UnreadableListNoteStore(base: fixture.notes)
        store.failsListing = true
        let browse = fixture.makeCoordinator(notes: store)
        browse.show(anchoredTo: nil, excluding: nil)
        #expect(browse.isVisible)
        #expect(browse.rowDescriptions == ["*library 라이브러리 열기"])
        #expect(fixture.logs.count == 1)
        #expect(fixture.logs.first?.contains("노트 목록을 읽지 못했습니다") == true)

        let input = try #require(browse.inputView)
        input.type("새 계획")
        #expect(browse.rowDescriptions == ["*create “새 계획” 새 노트 만들기", " separator", " library 라이브러리 열기"])
        input.doCommand(by: returnKey)
        #expect(fixture.routes == [.newNote(NewNoteRequest(draft: NoteDraft(title: "새 계획"), nextTo: nil))])
    }

    /// 열려 있는 동안 목록을 읽지 못하게 되면 보이던 목록을 그대로 두고 까닭을 기록한다. 다시 읽히면 따라온다.
    @Test func failedReloadKeepsTheListThatWasShown() async throws {
        defer { fixture.cleanUp(expectingLogs: true) }
        let store = UnreadableListNoteStore(base: fixture.notes)
        let browse = fixture.makeCoordinator(notes: store)
        browse.show(anchoredTo: nil, excluding: nil)
        let shown = browse.rowDescriptions
        #expect(shown.count == 9)
        #expect(fixture.logs.isEmpty)

        store.failsListing = true
        try fixture.notes.update(try id("api")) { $0.title = "API 메모" }
        var deadline = Date().addingTimeInterval(3)
        while fixture.logs.isEmpty, Date() < deadline { try await Task.sleep(for: .milliseconds(5)) }
        #expect(fixture.logs.count == 1)
        #expect(browse.rowDescriptions == shown)

        store.failsListing = false
        try fixture.notes.update(try id("api")) { $0.title = "API 기록" }
        deadline = Date().addingTimeInterval(3)
        while !browse.rowDescriptions.contains(where: { $0.contains("| API 기록 |") }), Date() < deadline {
            try await Task.sleep(for: .milliseconds(5))
        }
        #expect(browse.rowDescriptions.contains { $0.contains("| API 기록 |") })
        #expect(fixture.logs.count == 1)
    }

    // MARK: - 창 상태와 스페이스의 변경

    private func waitForRows(_ condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(3)
        while !condition(), Date() < deadline { try await Task.sleep(for: .milliseconds(5)) }
    }

    /// 열려 있는 동안 노트 창이 뜨고 내려가면 "떠 있는 노트"와 핀이 따라간다(노트 파일은 바뀌지 않아도).
    @Test func openListFollowsWindowStateChanges() async throws {
        defer { fixture.cleanUp() }
        browse.show(anchoredTo: nil, excluding: nil)
        #expect(rows[1].hasPrefix("*note today"))
        #expect(rows.contains(" note api | API Notes | Rate limit and Retry policy | - | -"))

        // api 노트의 창이 맨 앞에 떴고 home의 창은 내려갔다.
        try fixture.windowStates.set(NoteWindowState(isOpen: true, stackOrder: 99), for: try id("api"))
        try fixture.windowStates.set(NoteWindowState(isOpen: false, stackOrder: 4), for: try id("home"))
        try await waitForRows { rows.contains { $0.contains("note api") && $0.hasSuffix("| pin") } }

        #expect(rows == [
            " header 떠 있는 노트",
            " note api | API Notes | Rate limit and Retry policy | - | pin",
            "*note today | 오늘 할 일 | PR #482 리뷰, 배포 체크리스트 확인 | 2:12 PM | pin",
            " header 최근에 연 노트",
            " note home | 개인 | 치과 예약 전화 | - | -",
            " note release | 릴리즈 노트 초안 | 2.3 변경 사항 정리, 배포 순서 확인 | 내일 10:00 AM | -",
            " note untitled | 제목 없음 | 주말 장보기 목록 | - | -",
            " separator",
            " library 라이브러리 열기",
        ])
        // 잇달아 온 변경은 한 번에 다시 읽는다. 고른 줄은 같은 노트다.
        #expect(browse.listReadCount == 2)
    }

    /// "최근에 연 노트"는 창 상태에 적힌 마지막으로 연 때를 따른다. 적힌 것이 없는 노트는 고친 시각이다.
    @Test func recentSectionUsesTheRecordedOpenTimes() async throws {
        defer { fixture.cleanUp() }
        // api는 가장 오래전에 고친 노트지만 방금 열었다 닫았다.
        try fixture.windowStates.set(NoteWindowState(isOpen: false, lastOpened: TestClock.now), for: try id("api"))
        browse.show(anchoredTo: nil, excluding: nil)
        let recent = rows.drop { $0 != " header 최근에 연 노트" }.dropFirst().prefix(3)
        #expect(recent.map { $0.components(separatedBy: " | ")[0] } == [
            " note api", " note release", " note untitled",
        ])
    }

    /// 스페이스 목록이 바뀌어도 열려 있는 목록을 다시 만든다. 닫힌 뒤에는 듣지 않는다.
    @Test func openListFollowsSpaceChangesUntilItCloses() async throws {
        defer { fixture.cleanUp() }
        browse.show(anchoredTo: nil, excluding: nil)
        let reads = browse.listReadCount
        try fixture.spaces.replace(with: [Space(id: Sample.work, name: "일", icon: .emoji("💼"))])
        try await waitForRows { browse.listReadCount > reads }
        #expect(browse.listReadCount == reads + 1)

        try press(escapeKey)
        try fixture.spaces.replace(with: [])
        try fixture.windowStates.set(NoteWindowState(isOpen: true), for: try id("api"))
        try await Task.sleep(for: .milliseconds(50))
        #expect(browse.listReadCount == reads + 1)
    }

    // MARK: - 닫힘과 실패를 알리기

    /// 닫힐 때 포커스를 열기 전의 자리로 돌려줄지 알린다: esc와 `hide()`는 돌려주고, 줄을 골라 요청이
    /// 이루어졌을 때는 받은 쪽이 포커스를 정했으므로 돌려주지 않는다. 그때의 알림은 요청 뒤에 온다.
    @Test func dismissalTellsWhetherFocusShouldGoBack() throws {
        defer { fixture.cleanUp() }
        var events: [String] = []
        browse.onDismiss = { [fixture] in events.append("dismiss \($0) routes \(fixture.routes.count)") }

        browse.show(anchoredTo: nil, excluding: nil)
        try press(escapeKey)
        browse.show(anchoredTo: nil, excluding: nil)
        browse.hide()
        // 이미 닫히는 중이면 다시 알리지 않는다.
        browse.hide()
        browse.show(anchoredTo: nil, excluding: nil)
        try press(returnKey)

        #expect(events == ["dismiss true routes 0", "dismiss true routes 0", "dismiss false routes 1"])
        #expect(fixture.routes == [.openNote(try id("today"))])
    }

    /// 띄울 때 목록을 읽지 못하면 기록과 함께 App에 알린다. 열려 있는 동안의 실패는 기록만 한다.
    @Test func failedOpenIsReportedOnce() async throws {
        defer { fixture.cleanUp(expectingLogs: true) }
        let store = UnreadableListNoteStore(base: fixture.notes)
        let browse = fixture.makeCoordinator(notes: store)
        var failures: [Error] = []
        browse.onFailure = { failures.append($0) }

        browse.show(anchoredTo: nil, excluding: nil)
        #expect(failures.isEmpty)
        store.failsListing = true
        try fixture.notes.update(try id("api")) { $0.title = "API 메모" }
        let deadline = Date().addingTimeInterval(3)
        while fixture.logs.isEmpty, Date() < deadline { try await Task.sleep(for: .milliseconds(5)) }
        #expect(failures.isEmpty)
        browse.hide()

        browse.show(anchoredTo: nil, excluding: nil)
        #expect(failures.count == 1)
        #expect(failures.first as? StoreError == .unreadableFile(URL(fileURLWithPath: "/notes")))
        #expect(browse.isVisible)
    }

    /// 걸어 둔 알림은 노트 찾기가 없어질 때 모두 푼다.
    @Test func observersAreRemovedWhenTheCoordinatorGoesAway() throws {
        defer { fixture.cleanUp() }
        let center = CountingNotificationCenter()
        var coordinator: BrowseCoordinator? = fixture.makeCoordinator()
        coordinator?.notificationCenter = center
        coordinator?.show(anchoredTo: nil, excluding: nil)
        #expect(center.added == 2)
        coordinator?.show(anchoredTo: nil, excluding: nil)
        #expect(center.added == 2)
        #expect(center.removed == 0)
        coordinator?.window?.orderOut(nil)
        weak let released = coordinator
        coordinator = nil
        #expect(released == nil)
        #expect(center.removed == 2)
    }

    @Test func pastedLineBreaksBecomeSpaces() throws {
        defer { fixture.cleanUp() }
        browse.show(anchoredTo: nil, excluding: nil)
        try input().type("배포\n체크")
        #expect(try input().string == "배포 체크")
    }

    // MARK: - 닫히는 중에는 명령을 받지 않는다

    /// 검토에서 나온 문제: 검색어를 치고 esc를 누른 바로 뒤의 ↵(사라지는 `dur` 안)가 고른 줄을 열었다.
    @Test func returnRightAfterEscapeOpensNothing() throws {
        defer { fixture.cleanUp() }
        browse.show(anchoredTo: nil, excluding: nil)
        try input().type("배포")
        try press(escapeKey)
        #expect(!browse.isVisible)
        #expect(try !input().isEditable)
        let selected = selectedRow

        try press(returnKey)
        try press(downKey)
        #expect(fixture.routes.isEmpty)
        #expect(selectedRow == selected)

        // 다시 띄우면 전처럼 받는다.
        browse.show(anchoredTo: nil, excluding: nil)
        #expect(try input().isEditable)
        try press(returnKey)
        #expect(fixture.routes == [.openNote(try id("today"))])
    }

    /// 창을 내리고 높이를 맞추는 일은 움직임이 끝났다는 알림이 아니라 전환 시간에 걸려 있다: 화면이 꺼져
    /// 움직임이 나아가지 않아도 `dur` 뒤에는 마지막으로 정한 틀에 놓여 있고, 닫은 창은 내려가 있다.
    @Test func frameAndClosingSettleAfterTheTransitionTimeWhateverTheAnimationDid() async throws {
        defer { fixture.cleanUp() }
        browse.show(anchoredTo: nil, excluding: nil)
        let window = try #require(browse.window)
        try input().type("xyz")
        var deadline = Date().addingTimeInterval(3)
        while window.frame != browse.settledFrame, Date() < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(window.frame == browse.settledFrame)

        try press(escapeKey)
        deadline = Date().addingTimeInterval(3)
        while window.isVisible, Date() < deadline { try await Task.sleep(for: .milliseconds(10)) }
        #expect(!window.isVisible)
        #expect(window.alphaValue == 0)
    }

    // MARK: - 고른 줄의 답

    /// 검토에서 나온 문제: 고른 노트를 열지 못하면(파일이 없어짐) 알림은 뜨는데 포커스가 돌아오지 않았다.
    /// 이루어지지 못한 요청 뒤에는 포커스를 열기 전의 자리로 돌려줄 때라고 알린다.
    @Test func failedRouteClosesAndAsksToReturnFocus() throws {
        defer { fixture.cleanUp(expectingLogs: true) }
        var dismissals: [Bool] = []
        browse.onDismiss = { dismissals.append($0) }
        fixture.routeResult = { _ in .failed }

        browse.show(anchoredTo: nil, excluding: nil)
        try press(returnKey)
        #expect(fixture.routes == [.openNote(try id("today"))])
        #expect(!browse.isVisible)
        #expect(dismissals == [true])

        fixture.routeResult = { _ in .unconnected }
        browse.show(anchoredTo: nil, excluding: nil)
        try press(returnKey)
        #expect(dismissals == [true, true])
        #expect(fixture.logs.count == 1)
        #expect(fixture.logs.first?.contains("아직 이어지지 않은 요청") == true)
    }

    /// 요청이 돌아오기 전에 키 창에서 물러나도(고른 노트가 키 창이 됨, 실패 알림 창) 그 때문에 닫히지 않는다:
    /// 닫힘은 한 번만, 요청의 답에 맞는 포커스로 알린다.
    @Test func resigningKeyWhileARouteIsOutDoesNotDismissEarly() throws {
        defer { fixture.cleanUp() }
        let center = NotificationCenter()
        let browse = fixture.makeCoordinator()
        browse.notificationCenter = center
        var dismissals: [Bool] = []
        browse.onDismiss = { dismissals.append($0) }
        browse.show(anchoredTo: nil, excluding: nil)
        let window = try #require(browse.window)
        fixture.routeResult = { _ in
            center.post(name: NSWindow.didResignKeyNotification, object: window)
            return .failed
        }

        try #require(browse.inputView).doCommand(by: returnKey)
        #expect(dismissals == [true])
    }

    /// 이어지지 않은 요청을 보내는 줄은 내놓지 않는다: "라이브러리 열기"는 그 화면이 이어져 있을 때만 보인다.
    @Test func libraryRowIsHiddenWhileItsRouteIsNotConnected() throws {
        defer { fixture.cleanUp() }
        fixture.unconnectedRoutes = [.openLibrary]
        browse.show(anchoredTo: nil, excluding: nil)
        #expect(rows.count == 7)
        #expect(!rows.contains { $0.contains("library") })
        #expect(rows.last?.hasPrefix(" note api") == true)
        for _ in 0..<10 { try press(downKey) }
        #expect(selectedRow?.hasPrefix("*note api") == true)
        try input().type("새 계획")
        #expect(rows == ["*create “새 계획” 새 노트 만들기"])

        // 이어지면 다시 보인다.
        fixture.unconnectedRoutes = []
        try press(escapeKey)
        browse.show(anchoredTo: nil, excluding: nil)
        #expect(rows.last == " library 라이브러리 열기")
    }

    // MARK: - 목록을 읽지 못했을 때의 알림

    /// 검토에서 나온 문제: 띄울 때 목록을 읽지 못해 알림 창이 뜨면, 그 창이 키 창을 가져가는 바람에
    /// 노트 찾기가 스스로 닫혀 남은 줄("새 노트 만들기", "라이브러리 열기")을 볼 수 없었다.
    @Test func failureAlertTakingKeyDoesNotCloseTheList() throws {
        defer { fixture.cleanUp(expectingLogs: true) }
        let center = NotificationCenter()
        let store = UnreadableListNoteStore(base: fixture.notes)
        store.failsListing = true
        let browse = fixture.makeCoordinator(notes: store)
        browse.notificationCenter = center
        var dismissals: [Bool] = []
        var failures = 0
        browse.onDismiss = { dismissals.append($0) }
        browse.onFailure = { [weak browse] _ in
            failures += 1
            // 알림 창이 키 창이 되면 노트 찾기는 키 창에서 물러난다.
            center.post(name: NSWindow.didResignKeyNotification, object: browse?.window)
        }

        browse.show(anchoredTo: nil, excluding: nil)
        #expect(failures == 1)
        #expect(browse.isVisible)
        #expect(dismissals.isEmpty)
        #expect(browse.rowDescriptions == ["*library 라이브러리 열기"])

        // 알림이 끝난 뒤의 바깥 클릭은 전처럼 닫는다.
        center.post(name: NSWindow.didResignKeyNotification, object: browse.window)
        #expect(!browse.isVisible)
        #expect(dismissals == [false])
    }

    // MARK: - ⌘W

    /// ⌘W는 esc처럼 노트 찾기를 닫는다(테두리 없는 창은 `performClose`를 받지 못해 경고음만 났다).
    @Test func commandWClosesTheListLikeEscape() throws {
        defer { fixture.cleanUp() }
        var dismissals: [Bool] = []
        browse.onDismiss = { dismissals.append($0) }
        browse.show(anchoredTo: nil, excluding: nil)
        let event = try #require(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: .command,
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: browse.window?.windowNumber ?? 0, context: nil, characters: "ㅈ",
            charactersIgnoringModifiers: "ㅈ", isARepeat: false, keyCode: 13
        ))
        #expect(try input().performKeyEquivalent(with: event))
        #expect(!browse.isVisible)
        #expect(dismissals == [true])
        #expect(fixture.routes.isEmpty)
    }
}
