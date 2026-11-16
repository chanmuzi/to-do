import AppKit
import Foundation
import Models
import Routing
import Store
import Testing
@testable import FloatingNotes

/// `AppDelegate`가 조립하는 작은 조각들: 메뉴 막대 아이콘 켜고 끄기, 떠 있는 노트가 없을 때 띄우기,
/// 앱이 앞으로 왔을 때 노트를 키 창으로 만들지.
@Suite struct AppLaunchPiecesTests {
    private struct IconMissing: Error {}

    // MARK: - 메뉴 막대 아이콘

    /// 검토에서 나온 문제: 아이콘을 꺼 두었는데도 아이콘 파일이 없으면 앱이 켜지지 않았다.
    @Test func iconFileIsNotReadWhileTheIconIsOff() {
        var loads = 0
        var warnings: [String] = []
        let icon = MenuBarIconSwitch<String>(
            loadIcon: {
                loads += 1
                throw IconMissing()
            },
            makeItem: { _ in "메뉴 막대 항목" }, warn: { warnings.append($0) }
        )

        icon.apply(shown: false)

        #expect(loads == 0)
        #expect(warnings.isEmpty)
        #expect(icon.item == nil)
    }

    /// 켰는데 파일을 읽지 못하면 던지지 않고 경고를 남긴 채 아이콘 없이 간다.
    @Test func missingIconFileLeavesAWarningAndNoStatusItem() {
        var warnings: [String] = []
        let icon = MenuBarIconSwitch<String>(
            loadIcon: { throw MenuBarIcon.NotFound() }, makeItem: { _ in "메뉴 막대 항목" },
            warn: { warnings.append($0) }
        )

        icon.apply(shown: true)

        #expect(icon.item == nil)
        #expect(warnings.count == 1)
        #expect(warnings.first?.contains("menubar-icon.pdf") == true)
        #expect(warnings.first?.contains("아이콘 없이") == true)
    }

    @Test func iconIsLoadedOnceWhenTurnedOnAndDroppedWhenTurnedOff() {
        var loads = 0
        var made = 0
        let icon = MenuBarIconSwitch<Int>(
            loadIcon: {
                loads += 1
                return NSImage(size: NSSize(width: 18, height: 18))
            },
            makeItem: { _ in
                made += 1
                return made
            },
            warn: { _ in }
        )

        icon.apply(shown: true)
        icon.apply(shown: true)
        #expect(icon.item == 1)
        #expect(loads == 1)
        icon.apply(shown: false)
        #expect(icon.item == nil)
        icon.apply(shown: true)
        #expect(icon.item == 2)
    }

    // MARK: - Dock 아이콘 누르기

    /// 검토에서 나온 문제: Dock 아이콘을 눌렀는데 노트를 띄우지 못하면 기록만 남고 아무 일도 없어 보였다.
    /// 새 노트를 만들지 못했을 때와 같은 알림으로 까닭을 보여 준다.
    @Test func reopenThatCannotShowANoteTellsTheUser() throws {
        let fixture = try AppFixture()
        var shown: [(title: String, error: Error)] = []
        var warnings: [String] = []
        let presenter = FallbackNotePresenter(
            notes: fixture.notes, notePanels: fixture.notePanels, warn: { warnings.append($0) },
            presentFailure: { shown.append((title: $0, error: $1)) }
        )
        // 노트가 하나도 없고 노트 폴더에 쓸 수 없다: 빈 노트를 만들지 못한다.
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: fixture.root.path)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fixture.root.path)
            fixture.cleanUp()
        }

        presenter.handleReopen()

        #expect(shown.count == 1)
        #expect(shown.first?.title == "노트를 띄우지 못했습니다")
        #expect(shown.first?.error is StoreError)
        #expect(warnings.count == 1)
        #expect(fixture.notePanels.openNoteIDs.isEmpty)
    }

    @Test func reopenShowsHiddenNotesOrTheMostRecentNoteWithoutAnAlert() throws {
        let fixture = try AppFixture()
        defer { fixture.cleanUp() }
        var shown: [String] = []
        let presenter = FallbackNotePresenter(
            notes: fixture.notes, notePanels: fixture.notePanels, warn: { _ in },
            presentFailure: { title, _ in shown.append(title) }
        )
        let note = try fixture.notes.create(NoteDraft(title: "가장 최근 노트"))

        presenter.handleReopen()
        #expect(fixture.notePanels.openNoteIDs == [note.id])

        fixture.notePanels.toggleAllHidden()
        presenter.handleReopen()
        #expect(!fixture.notePanels.areNotesHidden)
        #expect(fixture.notePanels.openNoteIDs == [note.id])
        #expect(shown.isEmpty)
    }

    // MARK: - 앱이 앞으로 왔을 때

    /// 켜면서 온 활성화는 노트를 키 창으로 만들지 않는다. 그 뒤에 사용자가 앞으로 가져오면 만든다.
    @Test func launchActivationIsIgnoredAndLaterActivationsFocusTheNote() {
        var policy = ActivationFocusPolicy()
        // 다 켜기 전에 온 활성화.
        let whileLaunching = policy.shouldFocusNote(activatedAt: 9)
        policy.launchFinished(at: 10)
        let afterwards = policy.shouldFocusNote(activatedAt: 10.2)
        #expect(!whileLaunching)
        #expect(afterwards)

        var foreground = ActivationFocusPolicy()
        foreground.launchFinished(at: 10)
        // 다 켠 직후의 첫 활성화는 켜면서 온 것이다.
        let launchActivation = foreground.shouldFocusNote(activatedAt: 10.05)
        // 곧바로 다시 앞으로 가져와도(⌘Tab) 그것은 사용자가 한 것이다.
        let userActivation = foreground.shouldFocusNote(activatedAt: 10.4)
        #expect(!launchActivation)
        #expect(userActivation)
    }

    /// 뒤에서 켠 실행(로그인 항목, `open -g`)에는 켜면서 오는 활성화가 없다. 첫 활성화가 사용자의 것이다.
    @Test func firstActivationLongAfterABackgroundLaunchFocusesTheNote() {
        var policy = ActivationFocusPolicy()
        policy.launchFinished(at: 10)

        let first = policy.shouldFocusNote(activatedAt: 10 + ActivationFocusPolicy.launchGrace)
        let later = policy.shouldFocusNote(activatedAt: 500)
        #expect(first)
        #expect(later)
    }
}
