import AppKit
@_spi(Verification) import Capture
import Models
@_spi(Verification) @testable import NotePanel
import Routing
import Testing
@testable import FloatingNotes

/// 짧은 알림(D-041): 휴지통으로 보낸 뒤의 "되돌리기"와 캡처한 뒤의 "열기".
@MainActor
@Suite(.serialized) struct ToastTests {
    private let fixture: WiringFixture
    private let presenter: ToastPresenter
    private let toasts: AppToasts

    init() throws {
        fixture = try WiringFixture()
        presenter = ToastPresenter(theme: fixture.theme)
        // 시험은 시간을 기다리지 않는다: 사라지는 전환은 바로, 떠 있는 시간은 길게.
        presenter.transitionDuration = { 0 }
        presenter.holdDuration = 60
        let commands = fixture.commands
        toasts = AppToasts(
            presenter: presenter, notePanels: fixture.notePanels, capture: fixture.capture,
            notes: fixture.notes, router: fixture.router, undoTrash: { commands.undoOrRestoreTrash(nil) }
        )
        toasts.pointerScreen = { NSScreen.main }
    }

    private func clickAction() throws {
        let window = try #require(presenter.window)
        let button = try #require(window.contentView?.subviews.first { $0 is ToastActionButton })
        let location = button.convert(NSPoint(x: button.bounds.midX, y: button.bounds.midY), to: nil)
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            window.sendEvent(NSEvent.mouseEvent(
                with: type, location: location, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1
            )!)
        }
    }

    @Test func trashShowsAnUndoToastThatRestoresTheNoteOnARealPress() throws {
        defer { presenter.dismiss(); fixture.cleanUp() }
        let id = try fixture.open("버릴 노트", body: "글")
        fixture.notePanels.moveToTrash(id)
        #expect(presenter.content?.message == AppToasts.trashMessage)
        #expect(presenter.content?.actionTitle == "되돌리기")
        let window = try #require(presenter.window)
        #expect(window.isVisible)
        #expect(!window.canBecomeKey)
        #expect(!window.styleMask.contains(.titled))
        #expect((window as? NSPanel)?.styleMask.contains(.nonactivatingPanel) == true)

        try clickAction()
        #expect(fixture.notePanels.openNoteIDs == [id])
        #expect(!fixture.notePanels.canUndoTrash)
        #expect(!presenter.isVisible)
        #expect(!window.isVisible)
    }

    /// ⌘Z로 되살리면 알림을 거둔다. 어느 쪽으로든 되돌리기는 한 번만 된다.
    @Test func undoByShortcutDismissesTheToast() throws {
        defer { presenter.dismiss(); fixture.cleanUp() }
        let id = try fixture.open("버릴 노트", body: "글")
        fixture.notePanels.moveToTrash(id)
        #expect(presenter.isVisible)
        fixture.commands.undoOrRestoreTrash(nil)
        #expect(fixture.notePanels.openNoteIDs == [id])
        #expect(!presenter.isVisible)
        // 이미 되살렸으므로 알림의 동작이 남아 있어도 다시 하지 않는다.
        presenter.performAction()
        #expect(fixture.notePanels.openNoteIDs == [id])
    }

    /// "바로 뒤"가 지나면(다른 노트를 고침 등) 알림을 거둔다.
    @Test func toastGoesAwayWhenUndoIsNoLongerPossible() throws {
        defer { presenter.dismiss(); fixture.cleanUp() }
        let id = try fixture.open("버릴 노트", body: "글")
        _ = try fixture.notePanels.createNote()
        fixture.notePanels.moveToTrash(id)
        #expect(presenter.isVisible)
        fixture.notePanels.endTrashUndo()
        #expect(!presenter.isVisible)
    }

    /// 캡처한 노트의 창이 보이지 않으면 그 이름과 "열기"를 알리고, 누르면 그 노트가 뜬다.
    @Test func captureToastNamesTheNoteAndOpensIt() throws {
        defer { presenter.dismiss(); fixture.cleanUp() }
        let note = try fixture.notes.create(NoteDraft(title: "장보기"))
        toasts.captured(into: note.id)
        #expect(presenter.content?.message == "“장보기”에 넣었습니다")
        #expect(presenter.content?.actionTitle == "열기")
        try clickAction()
        #expect(fixture.notePanels.openNoteIDs == [note.id])
        #expect(!presenter.isVisible)
    }

    /// 제목이 없으면 "오늘 노트"라고 부른다. 그 노트의 창이 이미 보이면 알리지 않는다.
    @Test func captureToastUsesTodayNoteOrStaysQuietWhenTheNoteIsVisible() throws {
        defer { presenter.dismiss(); fixture.cleanUp() }
        let untitled = try fixture.notes.create(NoteDraft(title: ""))
        toasts.captured(into: untitled.id)
        #expect(presenter.content?.message == "“오늘 노트”에 넣었습니다")
        presenter.dismiss()

        let shown = try fixture.open("떠 있는 노트")
        toasts.captured(into: shown)
        #expect(!presenter.isVisible)
    }

    /// 상태는 전환이 끝났는지에 기대지 않는다: 거두면 곧바로 보이지 않는 것으로 친다.
    @Test func dismissChangesStateImmediately() {
        presenter.transitionDuration = { 10 }
        presenter.show(.init(kind: "k", message: "글", actionTitle: "동작"), on: NSScreen.main) {}
        #expect(presenter.isVisible)
        presenter.dismiss()
        #expect(!presenter.isVisible)
        #expect(presenter.content == nil)
        presenter.transitionDuration = { 0 }
        presenter.show(.init(kind: "k", message: "글", actionTitle: "동작"), on: NSScreen.main) {}
        presenter.dismiss()
        #expect(presenter.window?.isVisible == false)
        fixture.cleanUp()
    }

    @Test func placementIsBottomCentreOfTheVisibleArea() {
        let frame = ToastPlacement.frame(
            size: CGSize(width: 200, height: 34), visibleFrame: CGRect(x: 100, y: 50, width: 1000, height: 800),
            bottomFraction: 0.08
        )
        #expect(frame == CGRect(x: 500, y: 114, width: 200, height: 34))
    }
}
