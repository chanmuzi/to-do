import Models

/// 노트 저장소. 기능 모듈은 이 프로토콜만 보고 쓴다. 저장 방식이 바뀌어도 이 모양은 그대로 둔다.
@MainActor
public protocol NoteStoring: AnyObject {
    /// 모든 노트. 최근에 고친 것이 앞.
    func list() throws -> [Note]
    func load(_ id: NoteID) throws -> Note
    /// 새 노트를 만들어 곧바로 파일로 쓴다.
    func create(_ draft: NoteDraft) throws -> Note
    /// 곧바로 쓴다. 수정 시각이 채워진 노트를 돌려준다. 내용이 디스크와 같으면 쓰지 않는다.
    @discardableResult func save(_ note: Note) throws -> Note
    /// 잠시 뒤에 쓴다(자동 저장). 같은 노트를 다시 넘기면 앞의 것을 대신한다.
    /// 실패는 `StoreChange.Kind.saveFailed`로 알린다.
    func scheduleSave(_ note: Note)
    /// 미뤄 둔 저장을 지금 모두 쓴다. 창을 닫거나 앱을 끝낼 때 부른다.
    func flushPendingSaves() throws
    func moveToTrash(_ id: NoteID) throws
    /// 휴지통의 노트. 최근에 고친 것이 앞.
    func listTrash() throws -> [Note]
    @discardableResult func restoreFromTrash(_ id: NoteID) throws -> Note
    /// 변경을 알려 받는다. 돌려받은 값을 들고 있는 동안만 알림이 온다.
    func observe(_ handler: @escaping @MainActor (StoreChange) -> Void) -> StoreObservation
}
