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
        let whileLaunching = policy.decide(at: 9).reason == .showLibrary
        policy.launchFinished(at: 10)
        policy.didResignActive()
        let afterwards = policy.decide(at: 10.2).reason == .showLibrary
        #expect(!whileLaunching)
        #expect(afterwards)

        var foreground = ActivationFocusPolicy()
        foreground.launchFinished(at: 10)
        // 다 켠 직후의 첫 활성화는 켜면서 온 것이다.
        let launchActivation = foreground.decide(at: 10.05).reason == .showLibrary
        // 곧바로 다시 앞으로 가져와도(⌘Tab) 그것은 사용자가 한 것이다.
        foreground.didResignActive()
        let userActivation = foreground.decide(at: 10.4).reason == .showLibrary
        #expect(!launchActivation)
        #expect(userActivation)
    }

    /// 알림 창이나 캡처 바, 노트 찾기가 키 입력을 받는 중에 앱이 앞으로 오면(실패를 알리는 알림 창은 스스로
    /// 앱을 앞으로 가져온다) 요청된 창의 포커스를 지킨다. 그 활성화도 본 것으로 친다.
    @Test func activationWhileAnotherScreenHoldsKeyPreservesTheTarget() {
        var policy = ActivationFocusPolicy()
        policy.launchFinished(at: 10)

        let duringAlert = policy.decide(at: 500, explicitTarget: true).reason == .showLibrary
        policy.didResignActive()
        let afterwards = policy.decide(at: 501, explicitTarget: false).reason == .showLibrary
        #expect(!duringAlert)
        #expect(afterwards)

        // 다 켠 직후에 알림 창과 함께 온 활성화 다음의 활성화는 사용자의 것이다.
        var early = ActivationFocusPolicy()
        early.launchFinished(at: 10)
        let first = early.decide(at: 10.1, explicitTarget: true).reason == .showLibrary
        early.didResignActive()
        let second = early.decide(at: 10.3).reason == .showLibrary
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
        #expect(ActivationFocusPolicy.carbonTarget(nil) == .noEvent)
        #expect(ActivationFocusPolicy.carbonTarget(event) == .unspecified)
        var marker = 0
        withUnsafeMutablePointer(to: &marker) { pointer in
            var clickedWindow = UnsafeMutableRawPointer(pointer)
            let set = SetEventParameter(event, EventParamName(kEventParamWindowRef), EventParamType(typeWindowRef),
                                        MemoryLayout.size(ofValue: clickedWindow), &clickedWindow)
            #expect(set == noErr)
            #expect(ActivationFocusPolicy.carbonTarget(event) == .clickedWindow)
        }
    }

    @Test func releasedNoteClickTargetsOnlyItsActivation() {
        var policy = ActivationFocusPolicy()
        policy.launchFinished(at: 0)
        policy.windowPressedWhileInactive(at: 9.75)
        let clicked = policy.decide(at: 10).reason == .showLibrary
        policy.didResignActive()
        let switched = policy.decide(at: 11).reason == .showLibrary
        #expect(!clicked)
        #expect(switched)
    }

    /// 설치된 앱의 로그(10:11:01): 시스템이 먼저 활성화하고 누름은 그 뒤에 전달됐다.
    @Test func latePressKeepsTheWindowForTheWholeActivation() {
        var policy = ActivationFocusPolicy()
        policy.launchFinished(at: 0)
        _ = policy.decide(at: 5)
        policy.didResignActive()
        let first = policy.decide(at: 10, window: .floatWindow, mouseAge: 6.386, keyAge: 3.886)
        #expect(first.reason == .showLibrary)
        #expect(ActivationFocusPolicy.waitsForLatePress(window: .floatWindow))
        policy.adoptLatePress()
        let repeated = policy.decide(at: 10.05, window: .floatWindow, mouseAge: 6.4, keyAge: 3.9)
        #expect(repeated.reason == .localPress)
        #expect(repeated.reused)
        policy.didResignActive()
        #expect(policy.decide(at: 20).reason == .showLibrary)
    }

    @Test func onlyAFloatWindowUnderThePointerWaitsForALatePress() {
        #expect(!ActivationFocusPolicy.waitsForLatePress(window: .library))
        #expect(!ActivationFocusPolicy.waitsForLatePress(window: .external))
        #expect(!ActivationFocusPolicy.waitsForLatePress(window: .none))
    }

    @Test func helperReturnDependsOnEveryAppSinceResigning() {
        typealias Kind = ActivationHistory.AppKind
        let cases: [([Kind], ActivationDecision.Reason)] = [
            ([.accessory], .helperReturn), ([.prohibited], .helperReturn), ([.regular], .showLibrary),
            ([.accessory, .regular], .showLibrary), ([.regular, .accessory], .showLibrary), ([], .showLibrary)
        ]
        for (apps, expected) in cases {
            var policy = ActivationFocusPolicy()
            policy.launchFinished(at: 0)
            _ = policy.decide(at: 0)
            policy.didResignActive()
            var history = ActivationHistory()
            for app in apps { history.activated(app) }
            let result = policy.decide(at: 10, history: history, window: .floatWindow, mouseAge: 2.245, keyAge: 3.745)
            #expect(result.reason == expected)
            #expect(history.previous == (apps.last ?? .none))
        }
    }

    @Test func explicitTargetsAndWindowClicksTakePriorityOverHelperReturn() {
        var history = ActivationHistory()
        history.activated(.accessory)
        let state = ActivationDecision(launching: false, pendingAge: nil)
        #expect(state.reason(history: history, explicitTarget: true) == .explicitTarget)
        #expect(state.reason(history: history, carbonWindow: true) == .carbonWindow)
        #expect(state.reason(history: history, window: .floatWindow, mouseAge: 0) == .pointer)
        #expect(ActivationDecision(launching: false, pendingAge: 0).reason(history: history) == .localPress)
    }

    @Test func pointerActivationDecisions() {
        typealias Window = ActivationDecision.WindowKind
        typealias Reason = ActivationDecision.Reason
        let limit = ActivationFocusPolicy.pressLifetime
        // 창 종류, 왼쪽 누름 경과, 키 누름 경과, 기대 판단.
        let cases: [(Window, TimeInterval, TimeInterval, Reason)] = [
            (.floatWindow, 0, 1, .pointer), (.floatWindow, limit, 1, .pointer),
            (.floatWindow, limit.nextUp, 1, .showLibrary), (.floatWindow, -1, 1, .showLibrary),
            (.floatWindow, .infinity, .infinity, .showLibrary), (.floatWindow, .nan, 1, .showLibrary),
            (.library, 0, 1, .showLibrary), (.external, 0, 1, .showLibrary), (.none, 0, 1, .showLibrary),
            (.floatWindow, 0.2, 0.1, .showLibrary), (.floatWindow, 0.1, 0.2, .pointer),
        ]
        let state = ActivationDecision(launching: false, pendingAge: nil)
        for (window, mouse, key, expected) in cases {
            #expect(state.reason(window: window, mouseAge: mouse, keyAge: key) == expected)
        }
        #expect(state.reason(carbonWindow: true, window: .external) == .carbonWindow)
        #expect(state.reason(explicitTarget: true, window: .none) == .explicitTarget)
        let launch = ActivationDecision(launching: true, pendingAge: nil)
        #expect(launch.reason(window: .external, mouseAge: 0) == .launch)
    }

    @Test func pendingPressExpiresEvenWhenTheNoteDidNotActivateTheApp() {
        var policy = ActivationFocusPolicy()
        policy.launchFinished(at: 0)
        policy.windowPressedWhileInactive(at: 10)
        #expect(policy.decide(at: 10 + ActivationFocusPolicy.pressLifetime).reason == .localPress)
        policy.didResignActive()
        #expect(policy.decide(at: 10.5, window: .floatWindow, mouseAge: 0.5, keyAge: 0.1).reason == .showLibrary)
        policy.windowPressedWhileInactive(at: 20)
        let expired = (20 + ActivationFocusPolicy.pressLifetime).nextUp
        #expect(policy.decide(at: expired).reason == .showLibrary)
        #expect(policy.decide(at: expired, window: .floatWindow, mouseAge: 0).reason == .pointer)
    }

    @Test(arguments: [false, true])
    func duplicateActivationFromOneWindowPress(_ resignedBetweenNotifications: Bool) {
        var policy = ActivationFocusPolicy()
        policy.launchFinished(at: 0)
        policy.windowPressedWhileInactive(at: 10)
        let first = policy.decide(at: 10.025, appKit: .otherEvent, window: .floatWindow, mouseAge: 20.798, keyAge: 1.798)
        #expect(first.reason == .localPress && !first.reused)
        if resignedBetweenNotifications { policy.didResignActive() }
        let second = policy.decide(at: 10.097, appKit: .unspecified, window: .floatWindow, mouseAge: 20.877, keyAge: 1.877)
        #expect(second.reason == .localPress && second.reused)
        let late = policy.decide(at: 12, window: .external, keyAge: 0)
        #expect(late.reason == .localPress && late.reused)
        policy.didResignActive()
        #expect(policy.decide(at: 12.01).reason == .showLibrary)
    }

    @Test func explicitAgentActivationSurvivesRepeatedNotification() {
        var policy = ActivationFocusPolicy()
        policy.launchFinished(at: 0)
        #expect(policy.decide(at: 2, explicitTarget: true).reason == .explicitTarget)
        let second = policy.decide(at: 3)
        #expect(second.reason == .explicitTarget && second.reused)
    }

    /// 뒤에서 켠 실행(로그인 항목, `open -g`)에는 켜면서 오는 활성화가 없다. 첫 활성화가 사용자의 것이다.
    @Test func firstActivationLongAfterABackgroundLaunchShowsTheLibrary() {
        var policy = ActivationFocusPolicy()
        policy.launchFinished(at: 10)

        let first = policy.decide(at: 10 + ActivationFocusPolicy.launchGrace).reason == .showLibrary
        let later = policy.decide(at: 500).reason == .showLibrary
        #expect(first)
        #expect(later)
    }
}
