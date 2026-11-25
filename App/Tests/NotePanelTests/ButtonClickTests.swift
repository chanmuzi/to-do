import AppKit
import Models
import Routing
import Store
import Testing
import Theme
@_spi(Verification) @testable import NotePanel

/// 노트 창의 버튼을 실제 마우스 이벤트(누름과 뗌)로 누른다. 동작을 직접 부르지 않고 사용자가 누를 때와 같은
/// 길(`NSWindow.sendEvent`, `NSApplication.sendEvent`)로 넣는다.
///
/// 예전에 누름이 사라진 까닭 두 가지를 여기서 지킨다.
/// - 버튼 안의 아이콘(`NSImageView`)이 누름을 받았다. 아이콘 뷰는 `acceptsFirstMouse`가 거짓이라 키 창이 아니거나
///   앱이 뒤에 있을 때의 첫 누름을 AppKit이 버렸다(아이콘 한가운데를 누르면 아무 일도 없었다).
/// - 창 모서리 근처는 테두리 없는 창의 크기 조절 자리라, 그 안에 든 핀(오른쪽 위)과 닫기(오른쪽 아래)의 일부를
///   누르면 창이 크기 조절을 시작하고 버튼은 아무것도 받지 못했다.
@Suite @MainActor struct ButtonClickTests {
    private let fixture: NotePanelFixture

    init() throws {
        fixture = try NotePanelFixture()
    }

    private func buttons(in view: NSView) -> [IconButton] {
        view.subviews.flatMap { ($0 as? IconButton).map { [$0] } ?? buttons(in: $0) }
    }

    /// 버튼 안의 점들(가장자리 1pt 안쪽부터 4pt 간격, 마지막 줄과 칸은 가장자리 1pt 안쪽). 창 모서리 가까운 곳도 든다.
    private func grid(in view: NSView) -> [NSPoint] {
        func steps(_ length: CGFloat) -> [CGFloat] {
            Array(Set(Array(stride(from: 1.0, through: length - 1, by: 4)) + [length - 1])).sorted()
        }
        return steps(view.bounds.height).flatMap { y in steps(view.bounds.width).map { x in NSPoint(x: x, y: y) } }
    }

    private func openHoveredNote(_ draft: NoteDraft = NoteDraft(title: "제목", body: "하나\n둘")) throws
        -> (NotePanelCoordinator, NoteWindowController)
    {
        let coordinator = try fixture.makeCoordinator()
        let note = try fixture.notes.create(draft)
        try coordinator.open(note.id, focus: false)
        let controller = try #require(coordinator.controllers[note.id])
        controller.hoverOverride = true
        controller.root.topRow.advanceDrawer(by: 1)
        controller.root.layoutSubtreeIfNeeded()
        return (coordinator, controller)
    }

    /// 상단 줄과 오른쪽 아래의 모든 버튼: 버튼 안 어디를 눌러도 한 번 눌러 한 번 동작한다.
    /// 창이 키 창이 아니고(시험은 키 창을 만들지 않는다) 앱도 앞에 있지 않은 상태다.
    @Test func everyButtonActsOnceWhereverItIsPressed() throws {
        let (coordinator, controller) = try openHoveredNote()
        defer { fixture.cleanUp(coordinator) }
        let all = buttons(in: controller.root).filter { !$0.isHidden }
        #expect(Set(all.compactMap { $0.accessibilityLabel() }) == [
            "에이전트 열기", "더 보기", "항상 위에 고정", "창 닫기",
        ])
        let face = try #require(all.first { $0.accessibilityLabel() == "에이전트 열기" })
        RealClick.click(face)
        #expect(fixture.routes == [.openAgentWindow(controller.noteID)])

        for button in all {
            var pressed = 0
            button.onPress = { pressed += 1 }
            var missed: [NSPoint] = []
            for point in grid(in: button) {
                let before = pressed
                let outcome = RealClick.click(at: button.convert(point, to: nil), in: controller.panel)
                if outcome.swallowedByTracking || pressed != before + 1 { missed.append(point) }
            }
            #expect(missed.isEmpty, "\(button.accessibilityLabel() ?? "?"): \(missed)")
        }
    }

    /// 누름은 버튼 안의 아이콘이 아니라 버튼이 통째로 받고, 키 창이 아니어도 첫 누름을 받는다.
    /// (AppKit은 키 창이 아니거나 앱이 뒤에 있을 때 누른 뷰의 `acceptsFirstMouse`가 거짓이면 누름을 버린다.)
    @Test func theButtonItselfReceivesEveryPressAndAcceptsTheFirstOne() throws {
        let (coordinator, controller) = try openHoveredNote(NoteDraft(
            title: "제목", body: "본문", reminder: Date().addingTimeInterval(3600)
        ))
        defer { fixture.cleanUp(coordinator) }
        let clock = try #require(controller.reminderAnchor as? IconButton)
        let pressable = buttons(in: controller.root).filter { !$0.isHidden }
        #expect(pressable.contains(clock))
        #expect(clock.toolTip == clock.accessibilityLabel())
        #expect(clock.accessibilityPerformPress())
        #expect(fixture.routes == [.openReminderEditor(controller.noteID)])
        for view in pressable {
            for point in grid(in: view) {
                let hit = controller.panel.button(at: view.convert(point, to: nil))
                #expect(hit === view, "\(view): \(point)")
                #expect(hit?.acceptsFirstMouse(for: nil) == true)
            }
        }
    }

    /// 앱의 이벤트 길(`NSApplication.sendEvent`)로 넣어도 같다.
    @Test func pressesThroughTheApplicationEventPathAct() throws {
        let (coordinator, controller) = try openHoveredNote()
        defer { fixture.cleanUp(coordinator) }
        let pin = try #require(buttons(in: controller.root).first { $0.accessibilityLabel() == "항상 위에 고정" })
        #expect(controller.isPinned)
        RealClick.click(pin, via: { NSApplication.shared.sendEvent($0) })
        #expect(!controller.isPinned)
        RealClick.click(pin, via: { NSApplication.shared.sendEvent($0) })
        #expect(controller.isPinned)
    }

    /// 마우스가 막 들어와 버튼이 나타나는 중(`dur` 동안의 알파 전환)에도 첫 누름이 동작한다.
    @Test func pressDuringTheHoverFadeActs() throws {
        let coordinator = try fixture.makeCoordinator()
        defer { fixture.cleanUp(coordinator) }
        let note = try fixture.notes.create(NoteDraft(title: "제목"))
        try coordinator.open(note.id, focus: false)
        let controller = try #require(coordinator.controllers[note.id])
        controller.hoverOverride = false
        controller.root.layoutSubtreeIfNeeded()
        let pin = try #require(buttons(in: controller.root).first { $0.accessibilityLabel() == "항상 위에 고정" })
        // 나타나기 시작한 바로 그때 누른다.
        controller.hoverOverride = true
        RealClick.click(pin)
        #expect(!controller.isPinned)
        // 고정을 푼 핀도 서랍에서 보이는 즉시 새 위치에서 다시 누를 수 있다.
        if fixture.animates {
            #expect(controller.root.topRow.advanceDrawer(by: 0.3))
            #expect(pin.alphaValue > 0 && pin.alphaValue < 1)
        }
        RealClick.click(pin)
        #expect(controller.isPinned)
    }

    /// 글을 친 뒤, 다른 버튼을 막 쓴 뒤에도 버튼이 한 번에 동작한다.
    @Test func buttonsKeepWorkingAfterTypingAndAfterOtherButtons() throws {
        let (coordinator, controller) = try openHoveredNote()
        defer { fixture.cleanUp(coordinator) }
        controller.editor.focus()
        let textView = try #require(controller.panel.firstResponder as? NSTextView)
        textView.insertText("글자", replacementRange: textView.selectedRange())

        let all = buttons(in: controller.root)
        let pin = try #require(all.first { $0.accessibilityLabel() == "항상 위에 고정" })
        let menu = controller.makeMoreMenu()
        let close = try #require(all.first { $0.accessibilityLabel() == "창 닫기" })

        RealClick.click(pin)
        #expect(!controller.isPinned)
        menu.performActionForItem(at: menu.indexOfItem(withTitle: "새 노트"))
        RealClick.click(pin)
        #expect(controller.isPinned)
        RealClick.click(close)
        #expect(fixture.routes == [
            .newNote(NewNoteRequest(nextTo: controller.noteID)), .closeNoteWindow(controller.noteID),
        ])
    }

    /// 휴지통도 실제 누름으로 노트를 보낸다(본문 위에 겹쳐 뜬 버튼이 글자 칸에 누름을 빼앗기지 않는다).
    @Test func trashButtonMovesTheNoteToTheTrash() throws {
        let (coordinator, controller) = try openHoveredNote()
        defer { fixture.cleanUp(coordinator) }
        let id = controller.noteID
        let menu = controller.makeMoreMenu()
        menu.performActionForItem(at: menu.indexOfItem(withTitle: "휴지통으로 보내기"))
        #expect(coordinator.openNoteIDs.isEmpty)
        #expect(FileManager.default.fileExists(atPath: fixture.trashFile(id).path))
        #expect(coordinator.canUndoTrash)
    }

    /// 버튼을 누르면 보통 창처럼 앱이 앞으로 온다(D-025). 키 창을 끈 시험과 확인용 실행에서는 가져오지 않는다.
    @Test func pressingAButtonActivatesTheAppOnlyWhenKeyWindowsAreAllowed() throws {
        let (coordinator, controller) = try openHoveredNote()
        defer { fixture.cleanUp(coordinator) }
        var activations = 0
        coordinator.activateApp = { activations += 1 }
        coordinator.isAppActive = { false }
        let pin = try #require(buttons(in: controller.root).first { $0.accessibilityLabel() == "항상 위에 고정" })
        pin.onPress = {}

        RealClick.click(pin)
        #expect(activations == 0)

        coordinator.allowsKeyWindows = true
        controller.panel.allowsKey = false
        coordinator.noteButtonPressed()
        #expect(activations == 1)
        coordinator.isAppActive = { true }
        coordinator.noteButtonPressed()
        #expect(activations == 1)
        coordinator.allowsKeyWindows = false
    }

    /// 버튼을 누른 뒤 뗌이 오지 않았어도(창이 내려가는 등), 다음 누름은 그 버튼으로 가지 않는다.
    @Test func aLostReleaseDoesNotLeaveTheButtonPressed() throws {
        let (coordinator, controller) = try openHoveredNote()
        defer { fixture.cleanUp(coordinator) }
        let pin = try #require(buttons(in: controller.root).first { $0.accessibilityLabel() == "항상 위에 고정" })
        var pressed = 0
        pin.onPress = { pressed += 1 }
        let window = controller.panel
        let onPin = pin.convert(NSPoint(x: pin.bounds.midX, y: pin.bounds.midY), to: nil)
        window.sendEvent(RealClick.event(.leftMouseDown, at: onPin, in: window))
        // 뗌을 잃는다. 다음은 버튼이 아닌 상단 줄의 빈 곳을 누르고, 핀 위에서 뗀다.
        let row = controller.root.topRow
        let empty = row.convert(NSPoint(x: row.bounds.midX - 40, y: row.bounds.midY), to: nil)
        window.sendEvent(RealClick.event(.leftMouseDown, at: empty, in: window))
        window.sendEvent(RealClick.event(.leftMouseUp, at: onPin, in: window))
        #expect(pressed == 0)
        // 그 뒤의 보통 누름은 그대로 한 번 동작한다.
        RealClick.click(pin)
        #expect(pressed == 1)
    }

    /// 버튼이 아닌 곳(상단 줄의 빈 곳, 본문)으로 가는 누름은 창이 그대로 처리한다(끌기, 글자 선택).
    @Test func pressesOutsideButtonsAreLeftToTheWindow() throws {
        let (coordinator, controller) = try openHoveredNote()
        defer { fixture.cleanUp(coordinator) }
        let row = controller.root.topRow
        let empty = row.convert(NSPoint(x: row.bounds.midX - 40, y: row.bounds.midY), to: nil)
        #expect(controller.panel.button(at: empty) == nil)
        let body = controller.editor.view
        #expect(controller.panel.button(at: body.convert(NSPoint(x: 20, y: 10), to: nil)) == nil)
    }
}
