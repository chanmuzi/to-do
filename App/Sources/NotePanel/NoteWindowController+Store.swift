import Foundation
import Models
import Store

/// 노트 창이 저장소를 쓰는 곳. 노트를 통째로 덮어쓰지 않고 맡은 항목만 고친다(D-016).
/// 본문을 편집기에 넣는 규칙은 `NoteBodyEditing`의 약속을 따른다.
extension NoteWindowController {
    /// 지금 값에 `change`를 적용한다. `deferred`면 자동 저장(본문, 제목 입력), 아니면 곧바로 쓴다(색).
    func mutate(deferred: Bool, _ change: (inout Note) -> Void) {
        coordinator?.endTrashUndo()
        do {
            note = deferred
                ? try environment.notes.scheduleUpdate(noteID, change)
                : try environment.notes.update(noteID, change)
        } catch StoreError.noteNotFound {
            // 파일이 없어졌다. 저장소가 이 변경을 받지 못했을 수 있으므로 창이 들고 있는다.
            environment.log("노트 파일이 없어 변경을 저장하지 못했습니다(\(noteID))")
            var edited = note
            change(&edited)
            note = edited
            hasUnstoredEdits = true
            fileWentMissing()
        } catch {
            handleStoreFailure(error)
        }
    }

    /// 저장소에서 온 이 노트의 변경. 없어졌다는 알림은 `NotePanelCoordinator`가 받아 `fileWentMissing()`을 부른다.
    func storeDidChange(_ change: StoreChange) {
        switch (change.kind, change.origin) {
        case (.updated, .local):
            // 이 앱이 디스크에 썼다. 저장 실패는 풀린 것이고, 충돌은 사용자가 고를 때까지 남긴다.
            if case .saveFailed = problem { problem = nil }
            if problem == .fileMissing, !hasUnstoredEdits { problem = nil }
            // 이 창이 한 저장이면 본문이 편집기와 주고받은 것과 같아 편집기를 건드리지 않는다. 이 앱의 다른 곳이
            // 쓴 것(빠른 캡처가 덧붙인 줄)이면 달라져 있고, 그때는 편집기에도 넣는다(`syncEditorBody`).
            adoptStoreNote()
        case (.updated, .external):
            adoptStoreNote()
        case (.created, _):
            fileReappeared()
        case (.conflict, _):
            setProblem(.conflict)
        case (.saveFailed(let message), _):
            environment.log("노트를 저장하지 못했습니다(\(noteID)): \(message)")
            // 파일이 없어진 노트는 다시 저장할 곳이 없다. 고르게 하는 표시를 그대로 둔다.
            if problem != .fileMissing { setProblem(.saveFailed(message: message)) }
        case (.removed, _):
            break
        }
    }

    /// 저장소의 지금 값을 받아들인다(이 앱의 저장, 다른 프로그램이 고친 파일, 파일의 내용으로 되돌리기).
    /// 본문은 편집기와 주고받은 것과 다를 때만 편집기에 넣는다. 다시 읽으면 저장소의 충돌 기준도 갱신된다.
    private func adoptStoreNote() {
        let previous = note
        do {
            note = try environment.notes.load(noteID)
        } catch {
            handleStoreFailure(error)
            return
        }
        syncEditorBody()
        let remaining = Set(note.schedules.filter { !$0.isDeleted }.map(\.id))
        for item in previous.schedules where !item.isDeleted && !remaining.contains(item.id) {
            if let line = item.inlineSource?.line, line >= 0 { editor.scheduleRemoved(fromBodyLine: line) }
        }
        refreshChrome(animated: true)
    }

    /// 저장소의 본문이 편집기와 마지막으로 주고받은 본문과 다를 때만 편집기에 넘긴다. `text`에 넣지 않는다:
    /// 끝에 글이 붙은 것이면 붙은 글만(`appendFromOutside`), 아니면 새 본문을(`applyOutsideChange`) 넘겨
    /// 편집기가 달라진 곳만 바꾸고 커서, 접힘, 실행 취소 기록, 조합 중인 글자를 지키게 한다.
    private func syncEditorBody() {
        guard note.body != exchangedBody else { return }
        let old = exchangedBody.unicodeScalars
        let new = note.body.unicodeScalars
        exchangedBody = note.body
        if !old.isEmpty, new.count > old.count, new.starts(with: old) {
            var suffix = String.UnicodeScalarView()
            suffix.append(contentsOf: new.dropFirst(old.count))
            editor.appendFromOutside(String(suffix))
        } else {
            editor.applyOutsideChange(to: note.body)
        }
    }

    func resolveProblem(_ action: ProblemMenuAction) {
        switch action {
        case .keepMine:
            // 편집기가 가진 글을 쓰는 것이므로 편집기는 건드리지 않는다.
            resolve { note = try environment.notes.resolveConflict(noteID, keeping: .mine) }
        case .keepDisk:
            resolve {
                note = try environment.notes.resolveConflict(noteID, keeping: .disk)
                syncEditorBody()
            }
        case .retrySave:
            resolve { try flushOwnPendingSaves() }
        case .saveAsNewNote:
            coordinator?.replaceMissingNote(noteID)
        case .discard:
            coordinator?.discardMissingNote(noteID)
        }
    }

    private func resolve(_ work: () throws -> Void) {
        do {
            try work()
        } catch {
            handleStoreFailure(error)
            return
        }
        problem = nil
        refreshChrome(animated: true)
    }

    /// 미뤄 둔 변경을 모두 쓴다. 다른 노트가 실패한 것은 기록만 하고(그 노트의 창이 제 표시를 띄운다),
    /// 이 노트가 실패했을 때만 그 까닭을 던진다.
    private func flushOwnPendingSaves() throws {
        do {
            try environment.notes.flushPendingSaves()
        } catch StoreError.pendingSavesFailed(let failures) {
            for failure in failures where failure.id != noteID {
                environment.log("노트를 저장하지 못했습니다(\(failure.id)): \(failure.error)")
            }
            if let mine = failures.first(where: { $0.id == noteID }) { throw mine.error }
        }
    }

    /// 창을 내리기 전에 미뤄 둔 변경을 쓴다. 이 노트를 쓰지 못했으면 `false`(창을 남겨 표시가 보이게 한다).
    func flushBeforeClosing() -> Bool {
        flushPendingEdits()
        // 파일이 없어진 노트는 쓸 곳이 없다. 새 노트로 저장하거나 버릴 때까지 창을 남긴다.
        guard problem != .fileMissing else { return false }
        do {
            try flushOwnPendingSaves()
            return true
        } catch {
            handleStoreFailure(error)
            return false
        }
    }

    /// 고치던 제목을 마무리하고, 편집기가 아직 알리지 않은 본문을 받아 저장소에 넘긴다.
    /// 창을 내리기 전, 휴지통으로 보내기 전, 앱을 끝내기 전에 부른다.
    func flushPendingEdits() {
        root.topRow.endTitleEditing()
        editor.flushPendingChange()
    }

    /// 저장소가 던진 오류를 상단 줄의 표시로 바꾼다. 숨기지 않고 기록도 남긴다.
    func handleStoreFailure(_ error: Error) {
        environment.log("노트 저장소 오류(\(noteID)): \(error)")
        switch error {
        case StoreError.noteNotFound:
            fileWentMissing()
        case StoreError.conflict:
            setProblem(.conflict)
        case let error as StoreError:
            setProblem(.saveFailed(message: error.description))
        default:
            setProblem(.saveFailed(message: "\(error)"))
        }
    }

    // MARK: - 없어진 파일

    /// 쓰지 못한 글이나 풀지 않은 문제가 있는지. 있으면 파일이 없어져도 창을 닫지 않는다.
    var hasUnwrittenWork: Bool {
        problem != nil || hasUnstoredEdits || environment.notes.hasPendingChanges(noteID)
    }

    /// 아무것도 적지 않았고(`Note.isBlank`) 풀지 않은 문제나 쓰지 못한 글도 없다. 이때만 창과 함께 지운다.
    var isBlankAndSettled: Bool {
        !hasUnwrittenWork && latestNote.isBlank
    }

    /// 쓰지 못한 변경까지 든 이 노트의 지금 값.
    var latestNote: Note {
        // 저장소가 받지 못한 변경은 창만 들고 있고, 그때의 `note`가 가장 새 값이다.
        guard !hasUnstoredEdits, environment.notes.hasPendingChanges(noteID),
              let pending = try? environment.notes.load(noteID)
        else { return note }
        return pending
    }

    /// 노트 파일이 없어졌다(다른 프로그램이 지움). 쓰지 못한 글이 있으면 창을 남기고 표시를 띄워
    /// 새 노트로 저장할지 버릴지 고르게 한다. 없으면 창을 내린다.
    func fileWentMissing() {
        if hasUnwrittenWork {
            if problem != .fileMissing { setProblem(.fileMissing) }
        } else {
            coordinator?.noteDisappeared(noteID)
        }
    }

    /// 같은 이름의 파일이 다시 생겼다(동기화 도구가 지웠다 만든 경우 등).
    private func fileReappeared() {
        guard problem == .fileMissing else {
            adoptStoreNote()
            return
        }
        if environment.notes.hasPendingChanges(noteID) {
            // 저장소에 남은 변경을 다시 써 본다. 그사이 파일 내용이 달라졌으면 충돌로 넘어가 사용자가 고른다.
            resolve { note = try environment.notes.update(noteID) { _ in } }
        } else if !hasUnstoredEdits {
            problem = nil
            adoptStoreNote()
        }
        // 저장소가 받지 못한 변경만 창에 남아 있으면 돌아온 파일을 덮어쓰지 않는다. 표시를 그대로 두고 고르게 한다.
    }

    func setProblem(_ newProblem: NoteProblem) {
        problem = newProblem
        refreshChrome(animated: true)
    }
}
