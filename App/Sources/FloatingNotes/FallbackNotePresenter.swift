import Foundation
import NotePanel
import Store

/// 떠 있는 노트가 없을 때 하나를 띄우는 곳(켤 때, Dock 아이콘을 눌렀을 때).
struct FallbackNotePresenter {
    static let failureTitle = "노트를 띄우지 못했습니다"

    let notes: any NoteStoring
    let notePanels: NotePanelCoordinator
    let warn: (String) -> Void
    /// 사용자가 시킨 일을 하지 못했을 때 알리는 곳(제목, 까닭).
    let presentFailure: (String, Error) -> Void

    /// 노트가 하나도 없으면 빈 노트를 새로 만든다(안내 문구 없이 커서만 있는 노트, spec 16과 규칙 3).
    /// 있으면 가장 최근에 고친 노트를 띄운다.
    func showFallbackNote() throws {
        let listing = try notes.list()
        for failure in listing.failures {
            warn("노트 파일을 읽지 못해 건너뜁니다: \(failure.error)")
        }
        if let recent = listing.notes.first {
            try notePanels.open(recent.id)
        } else {
            try notePanels.createNote()
        }
    }

    /// Dock 아이콘을 눌렀다: 숨긴 노트를 되돌리고, 떠 있는 노트가 없으면 하나를 띄운다. 그리고 맨 앞 노트가
    /// 키 창이 된다(사용자가 앱을 일부러 앞으로 가져온 것이다, D-025).
    /// 띄우지 못하면 기록만 하지 않고 알린다. 눌렀는데 아무 일도 없는 것처럼 보이지 않게 한다.
    func handleReopen() {
        if notePanels.areNotesHidden {
            notePanels.toggleAllHidden()
        } else if notePanels.openNoteIDs.isEmpty {
            do {
                try showFallbackNote()
            } catch {
                warn("\(Self.failureTitle): \(error)")
                presentFailure(Self.failureTitle, error)
                return
            }
        }
        notePanels.focusFrontmostNote()
    }
}
