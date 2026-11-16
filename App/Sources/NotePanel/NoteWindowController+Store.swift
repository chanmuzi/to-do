import Foundation
import Models
import Store

/// 노트 창이 저장소를 쓰는 곳. 노트를 통째로 덮어쓰지 않고 맡은 항목만 고친다(D-016).
extension NoteWindowController {
    /// 지금 값에 `change`를 적용한다. `deferred`면 자동 저장(본문, 제목 입력), 아니면 곧바로 쓴다(색).
    func mutate(deferred: Bool, _ change: (inout Note) -> Void) {
        do {
            note = deferred
                ? try environment.notes.scheduleUpdate(noteID, change)
                : try environment.notes.update(noteID, change)
        } catch {
            handleStoreFailure(error)
        }
    }

    /// 저장소에서 온 이 노트의 변경.
    func storeDidChange(_ change: StoreChange) {
        switch change.kind {
        case .created:
            reload()
        case .updated:
            // 이 앱이 디스크에 썼다는 알림이면 저장 실패는 풀린 것이다. 충돌은 사용자가 고를 때까지 남긴다.
            if change.origin == .local, case .saveFailed = problem { problem = nil }
            reload()
        case .conflict:
            setProblem(.conflict)
        case .saveFailed(let message):
            environment.log("노트를 저장하지 못했습니다(\(noteID)): \(message)")
            setProblem(.saveFailed(message: message))
        case .removed:
            break // 창을 내리는 일은 NotePanelCoordinator가 한다.
        }
    }

    /// 저장소의 지금 값을 다시 읽어 화면에 반영한다. 다른 프로그램이 고친 내용도 이때 들어온다.
    /// 다시 읽으면 저장소의 충돌 기준도 갱신된다.
    func reload() {
        do {
            note = try environment.notes.load(noteID)
        } catch {
            handleStoreFailure(error)
            return
        }
        if editor.text != note.body { editor.text = note.body }
        refreshChrome(animated: true)
    }

    func resolveProblem(_ action: ProblemMenuAction) {
        do {
            switch action {
            case .keepMine: note = try environment.notes.resolveConflict(noteID, keeping: .mine)
            case .keepDisk: note = try environment.notes.resolveConflict(noteID, keeping: .disk)
            case .retrySave: try environment.notes.flushPendingSaves()
            }
        } catch {
            handleStoreFailure(error)
            return
        }
        problem = nil
        if editor.text != note.body { editor.text = note.body }
        refreshChrome(animated: true)
    }

    /// 창을 내리기 전에 미뤄 둔 변경을 쓴다. 이 노트를 쓰지 못했으면 `false`(창을 남겨 표시가 보이게 한다).
    func flushBeforeClosing() -> Bool {
        root.topRow.endTitleEditing()
        do {
            try environment.notes.flushPendingSaves()
            return true
        } catch StoreError.pendingSavesFailed(let failures) {
            for failure in failures where failure.id != noteID {
                environment.log("노트를 저장하지 못했습니다(\(failure.id)): \(failure.error)")
            }
            guard let mine = failures.first(where: { $0.id == noteID }) else { return true }
            handleStoreFailure(mine.error)
            return false
        } catch {
            handleStoreFailure(error)
            return false
        }
    }

    /// 저장소가 던진 오류를 상단 줄의 표시로 바꾼다. 숨기지 않고 기록도 남긴다.
    func handleStoreFailure(_ error: Error) {
        environment.log("노트 저장소 오류(\(noteID)): \(error)")
        switch error {
        case StoreError.noteNotFound:
            coordinator?.noteDisappeared(noteID)
        case StoreError.conflict:
            setProblem(.conflict)
        case let error as StoreError:
            setProblem(.saveFailed(message: error.description))
        default:
            setProblem(.saveFailed(message: "\(error)"))
        }
    }

    private func setProblem(_ newProblem: NoteProblem) {
        problem = newProblem
        refreshChrome(animated: true)
    }
}
