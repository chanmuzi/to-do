import Models

/// 노트 저장소에서 일어난 일 하나.
public struct StoreChange: Hashable, Sendable {
    public enum Kind: Hashable, Sendable {
        case created
        case updated
        /// 휴지통으로 갔거나 파일이 없어졌다.
        case removed
        /// 미뤄 둔 저장(`scheduleSave`)이 실패했다. 노트 내용은 아직 디스크에 없다.
        case saveFailed(message: String)
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
