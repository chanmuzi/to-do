import CoreGraphics
import Models
import Store

/// 노트 창의 틀, 핀, 열림 상태를 `WindowStateStore`에 적는 곳(D-003). 노트 창은 이 타입만 거쳐 상태를 남긴다.
struct WindowStateRecorder {
    let store: WindowStateStore
    /// 상태 파일을 쓰지 못했을 때. 창은 계속 쓸 수 있으므로 기록만 남긴다.
    let log: (String) -> Void

    /// 저장된 상태. 한 번도 띄운 적이 없으면 기본값(핀 켜짐, spec 4.1).
    func state(for id: NoteID) -> NoteWindowState {
        store.state(for: id) ?? NoteWindowState()
    }

    /// 앱을 다시 켤 때 되살릴 노트.
    var openNoteIDs: [NoteID] {
        store.all.filter(\.value.isOpen).keys.sorted { $0.rawValue < $1.rawValue }
    }

    func recordOpened(_ id: NoteID, frame: CGRect, isPinned: Bool) {
        write(id) { _ in NoteWindowState(frame: WindowFrame(frame), isPinned: isPinned, isOpen: true) }
    }

    func recordFrame(_ id: NoteID, frame: CGRect) {
        write(id) { NoteWindowState(frame: WindowFrame(frame), isPinned: $0.isPinned, isOpen: $0.isOpen) }
    }

    func recordPinned(_ id: NoteID, isPinned: Bool) {
        write(id) { NoteWindowState(frame: $0.frame, isPinned: isPinned, isOpen: $0.isOpen) }
    }

    /// 창만 닫았다. 틀과 핀은 다시 띄울 때를 위해 남긴다.
    func recordClosed(_ id: NoteID) {
        write(id) { NoteWindowState(frame: $0.frame, isPinned: $0.isPinned, isOpen: false) }
    }

    /// 노트가 없어졌다(휴지통, 파일 삭제).
    func forget(_ id: NoteID) {
        do {
            try store.remove(id)
        } catch {
            log("창 상태를 지우지 못했습니다(\(id)): \(error)")
        }
    }

    private func write(_ id: NoteID, _ change: (NoteWindowState) -> NoteWindowState) {
        do {
            try store.set(change(state(for: id)), for: id)
        } catch {
            log("창 상태를 저장하지 못했습니다(\(id)): \(error)")
        }
    }
}
