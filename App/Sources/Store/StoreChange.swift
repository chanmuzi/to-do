import Models

/// 노트 저장소에서 일어난 일 하나.
public struct StoreChange: Hashable, Sendable {
    public enum Kind: Hashable, Sendable {
        case created
        case updated
        /// 휴지통으로 갔거나 파일이 없어졌다. 다른 프로그램이 지운 경우(`.external`) 쓰지 않은 변경은
        /// 저장소에 남아 있다(`hasPendingChanges`). 새 노트로 옮기거나 `discardPendingChanges`로 버린다.
        case removed
        /// 미뤄 둔 저장(`scheduleUpdate`)이 실패했다. 고친 내용은 저장소에 남아 있고 디스크에는 없다.
        case saveFailed(message: String)
        /// 쓰지 않은 변경이 있는 노트의 파일을 다른 프로그램이 고쳤다. 저장을 멈췄다.
        /// `resolveConflict(_:keeping:)`로 풀 때까지 그 노트는 디스크에 쓰지 않는다.
        case conflict
    }

    public enum Origin: Hashable, Sendable {
        /// 이 앱이 저장소 API로 한 일.
        case local
        /// 다른 프로그램이 노트 폴더의 파일을 바꿨다.
        case external
    }

    public let id: NoteID
    public let kind: Kind
    public let origin: Origin

    public init(id: NoteID, kind: Kind, origin: Origin) {
        self.id = id
        self.kind = kind
        self.origin = origin
    }
}

/// `observe`가 돌려주는 표. `cancel()`을 부르거나 이 값이 사라지면 알림이 멈춘다.
@MainActor
public final class StoreObservation {
    private var onCancel: (@MainActor () -> Void)?

    init(onCancel: @escaping @MainActor () -> Void) {
        self.onCancel = onCancel
    }

    public func cancel() {
        onCancel?()
        onCancel = nil
    }

    isolated deinit {
        onCancel?()
    }
}
