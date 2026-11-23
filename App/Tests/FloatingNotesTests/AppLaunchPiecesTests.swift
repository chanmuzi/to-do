import AppKit
import Carbon
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

    // MARK: - 앱이 앞으로 왔을 때

    /// 첫 실행의 복원을 지키고 다음 앱 전환에서 라이브러리를 연다.
    @Test func launchActivationIsIgnoredAndLaterActivationsShowTheLibrary() {
        var policy = ActivationFocusPolicy()
        // 다 켜기 전에 온 활성화.
        let whileLaunching = policy.shouldShowLibrary(activatedAt: 9)
        policy.launchFinished(at: 10)
        let afterwards = policy.shouldShowLibrary(activatedAt: 10.2)
        #expect(!whileLaunching)
        #expect(afterwards)

        var foreground = ActivationFocusPolicy()
        foreground.launchFinished(at: 10)
        // 다 켠 직후의 첫 활성화는 켜면서 온 것이다.
        let launchActivation = foreground.shouldShowLibrary(activatedAt: 10.05)
        // 곧바로 다시 앞으로 가져와도(⌘Tab) 그것은 사용자가 한 것이다.
        let userActivation = foreground.shouldShowLibrary(activatedAt: 10.4)
        #expect(!launchActivation)
        #expect(userActivation)
    }

    /// 알림 창이나 캡처 바, 노트 찾기가 키 입력을 받는 중에 앱이 앞으로 오면(실패를 알리는 알림 창은 스스로
    /// 앱을 앞으로 가져온다) 요청된 창의 포커스를 지킨다. 그 활성화도 본 것으로 친다.
    @Test func activationWhileAnotherScreenHoldsKeyPreservesTheTarget() {
        var policy = ActivationFocusPolicy()
        policy.launchFinished(at: 10)

        let duringAlert = policy.shouldShowLibrary(activatedAt: 500, hasExplicitTarget: true)
        let afterwards = policy.shouldShowLibrary(activatedAt: 501, hasExplicitTarget: false)
        #expect(!duringAlert)
        #expect(afterwards)

        // 다 켠 직후에 알림 창과 함께 온 활성화 다음의 활성화는 사용자의 것이다.
        var early = ActivationFocusPolicy()
        early.launchFinished(at: 10)
        let first = early.shouldShowLibrary(activatedAt: 10.1, hasExplicitTarget: true)
        let second = early.shouldShowLibrary(activatedAt: 10.3)
        #expect(!first)
        #expect(second)
    }

    @Test func activationEventIdentifiesAClickBeforeTheWindowReceivesIt() throws {
        var created: EventRef?
        let status = CreateEvent(nil, OSType(kEventClassApplication), UInt32(kEventAppActivated),
                                 GetCurrentEventTime(), 0, &created)
        #expect(status == noErr)
        let event = try #require(created)
        defer { ReleaseEvent(event) }
        #expect(!ActivationFocusPolicy.activationClickedWindow(event))
        var marker = 0
        withUnsafeMutablePointer(to: &marker) { pointer in
            var clickedWindow = UnsafeMutableRawPointer(pointer)
            let set = SetEventParameter(event, EventParamName(kEventParamWindowRef), EventParamType(typeWindowRef),
                                        MemoryLayout.size(ofValue: clickedWindow), &clickedWindow)
            #expect(set == noErr)
            #expect(ActivationFocusPolicy.activationClickedWindow(event))
        }
    }

    @Test func releasedNoteClickTargetsOnlyItsActivation() {
        var policy = ActivationFocusPolicy()
        policy.launchFinished(at: 0)
        policy.notePressedWhileInactive()
        let clicked = policy.shouldShowLibrary(activatedAt: 10)
        let switched = policy.shouldShowLibrary(activatedAt: 11)
        #expect(!clicked)
        #expect(switched)
    }

    /// 뒤에서 켠 실행(로그인 항목, `open -g`)에는 켜면서 오는 활성화가 없다. 첫 활성화가 사용자의 것이다.
    @Test func firstActivationLongAfterABackgroundLaunchShowsTheLibrary() {
        var policy = ActivationFocusPolicy()
        policy.launchFinished(at: 10)

        let first = policy.shouldShowLibrary(activatedAt: 10 + ActivationFocusPolicy.launchGrace)
        let later = policy.shouldShowLibrary(activatedAt: 500)
        #expect(first)
        #expect(later)
    }
}
