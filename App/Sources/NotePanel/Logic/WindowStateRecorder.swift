import CoreGraphics
import Models
import Store

/// 노트 창의 틀, 핀, 열림 상태, 겹친 차례를 `WindowStateStore`에 적는 곳(D-003). 노트 창은 이 타입만 거쳐 상태를 남긴다.
struct WindowStateRecorder {
    let store: WindowStateStore
    /// 상태 파일을 쓰지 못했을 때. 창은 계속 쓸 수 있으므로 기록만 남긴다.
    let log: (String) -> Void

    /// 저장된 상태. 한 번도 띄운 적이 없으면 기본값(핀 켜짐, spec 4.1).
    func state(for id: NoteID) -> NoteWindowState {
        store.state(for: id) ?? NoteWindowState()
    }

    /// 앱을 다시 켤 때 되살릴 노트. 뒤에 있던 것부터 적혀 있어, 이 차례대로 띄우면 마지막 것이 맨 앞에 온다.
    var openNoteIDs: [NoteID] {
        store.all.filter(\.value.isOpen)
            .sorted { ($0.value.stackOrder ?? 0, $0.key.rawValue) < ($1.value.stackOrder ?? 0, $1.key.rawValue) }
            .map(\.key)
    }

    /// 뒤에서 앞으로 겹친 차례로 늘어놓는다. 앞으로 온 적이 없는 것은 주어진 차례를 지킨 채 맨 뒤에 둔다.
    func backToFront(_ ids: [NoteID]) -> [NoteID] {
        ids.enumerated()
            .map { (offset: $0.offset, id: $0.element, order: state(for: $0.element).stackOrder ?? 0) }
            .sorted { ($0.order, $0.offset) < ($1.order, $1.offset) }
            .map(\.id)
    }

    func recordOpened(_ id: NoteID, frame: CGRect, isPinned: Bool) {
        write(id) {
            NoteWindowState(frame: WindowFrame(frame), isPinned: isPinned, isOpen: true, stackOrder: $0.stackOrder)
        }
    }

    func recordFrame(_ id: NoteID, frame: CGRect) {
        write(id) {
            NoteWindowState(
                frame: WindowFrame(frame), isPinned: $0.isPinned, isOpen: $0.isOpen, stackOrder: $0.stackOrder
            )
        }
    }

    func recordPinned(_ id: NoteID, isPinned: Bool) {
        write(id) {
            NoteWindowState(frame: $0.frame, isPinned: isPinned, isOpen: $0.isOpen, stackOrder: $0.stackOrder)
        }
    }

    /// 창이 맨 앞으로 왔다(띄움, 키 창이 됨). 이미 맨 앞이면 쓰지 않는다.
    func recordFronted(_ id: NoteID) {
        let others = store.all.filter { $0.key != id }.values.compactMap(\.stackOrder).max() ?? 0
        if let current = state(for: id).stackOrder, current > others { return }
        write(id) {
            NoteWindowState(frame: $0.frame, isPinned: $0.isPinned, isOpen: $0.isOpen, stackOrder: others + 1)
        }
    }

    /// 창만 닫았다. 틀과 핀은 다시 띄울 때를 위해 남긴다.
    func recordClosed(_ id: NoteID) {
        write(id) {
            NoteWindowState(frame: $0.frame, isPinned: $0.isPinned, isOpen: false, stackOrder: $0.stackOrder)
        }
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
