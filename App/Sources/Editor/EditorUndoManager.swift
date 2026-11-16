import AppKit

/// 편집기의 되돌리기 창구. 기록은 `EditorController`가 직접 들고(`UndoHistory`), 이것은 메뉴와 텍스트 뷰가
/// 아는 `UndoManager`의 모양으로 그 기록을 잇기만 한다. 등록(`registerUndo`)은 쓰지 않는다.
///
/// - `beginUndoGrouping`과 `endUndoGrouping` 사이의 편집은 한 단계가 된다(확인용 실행 파일과 테스트).
/// - 묶음을 열지 않았으면 런 루프 한 차례의 편집이 한 단계가 되고, 이어 친 글자는 한 단계로 합친다.
final class EditorUndoManager: UndoManager {
    weak var controller: EditorController?
    private var level = 0
    private var replaying = (undo: false, redo: false)

    override init() {
        super.init()
        // 텍스트 뷰가 제 되돌리기 동작을 여기에 적지 않게 한다. 기록은 편집기가 든다.
        disableUndoRegistration()
    }

    override var canUndo: Bool { MainActor.assumeIsolated { controller?.history.canUndo ?? false } }
    override var canRedo: Bool { MainActor.assumeIsolated { controller?.history.canRedo ?? false } }
    override var groupingLevel: Int { level }
    override var isUndoing: Bool { replaying.undo }
    override var isRedoing: Bool { replaying.redo }

    override func beginUndoGrouping() {
        if level == 0 { MainActor.assumeIsolated { controller?.closeUndoRecord() } }
        level += 1
    }

    override func endUndoGrouping() {
        guard level > 0 else { return }
        level -= 1
        if level == 0 { MainActor.assumeIsolated { controller?.closeUndoRecord() } }
    }

    override func undo() {
        replaying.undo = true
        MainActor.assumeIsolated { controller?.replayUndo(redo: false) }
        replaying.undo = false
    }

    override func redo() {
        replaying.redo = true
        MainActor.assumeIsolated { controller?.replayUndo(redo: true) }
        replaying.redo = false
    }

    override func undoNestedGroup() {
        undo()
    }

    override func removeAllActions() {
        MainActor.assumeIsolated { controller?.history = UndoHistory() }
    }

    override func removeAllActions(withTarget target: Any) {}
}
