import Models

/// 노트 저장소. 기능 모듈은 이 프로토콜만 보고 쓴다. 저장 방식이 바뀌어도 이 모양은 그대로 둔다.
///
/// 노트의 지금 값은 저장소가 들고 있다. 호출하는 쪽은 노트를 통째로 넘겨 덮어쓰지 않고,
/// 바꿀 항목만 `update`/`scheduleUpdate`의 클로저에서 고친다. 클로저는 아직 디스크에 쓰지 않은
/// 변경까지 들어 있는 지금 값을 받으므로, 편집기(본문)와 노트 창(제목·색·리마인더)이
/// 같은 노트를 따로 고쳐도 서로의 변경을 지우지 않는다.
///
/// 던지는 오류는 모두 `StoreError`다.
@MainActor
public protocol NoteStoring: AnyObject {
    /// 모든 노트(아직 쓰지 않은 변경 포함). 읽지 못한 파일은 `failures`에 담고 나머지를 돌려준다.
    func list() throws -> NoteListing
    /// 노트의 지금 값(아직 쓰지 않은 변경 포함). 쓰지 않은 변경이 없으면 디스크에서 읽고,
    /// 그 내용을 "호출하는 쪽이 본 내용"으로 기억한다(충돌 판정의 기준).
    func load(_ id: NoteID) throws -> Note
    /// 새 노트를 만들어 곧바로 파일로 쓴다. 파일을 새로 만드는 것은 이 호출뿐이다.
    func create(_ draft: NoteDraft) throws -> Note

    /// 지금 값에 `mutate`를 적용하고 곧바로 쓴다. 미뤄 둔 변경도 함께 쓴다.
    /// `id`, `created`, `modified`는 바꿀 수 없다. 바뀐 것이 없으면 쓰지 않는다.
    /// - Throws: 노트 폴더에 파일이 없으면 `noteNotFound`(파일을 만들지 않는다).
    ///   다른 프로그램이 파일을 고쳤으면 `conflict`(쓰지 않고, 변경은 저장소에 남는다).
    @discardableResult func update(_ id: NoteID, _ mutate: (inout Note) -> Void) throws -> Note
    /// 지금 값에 `mutate`를 적용하고 잠시 뒤에 쓴다(자동 저장). 돌려주는 값은 적용한 뒤의 지금 값.
    /// 마지막 호출 뒤 기본 0.5초, 계속 고치는 중이어도 첫 변경 뒤 기본 3초 안에 쓴다.
    /// 쓰다가 실패하면 `StoreChange.Kind.saveFailed`, 충돌이면 `.conflict`, 그사이 파일이 없어졌으면
    /// `.removed`(`.external`)로 알리고 변경은 남겨 둔다.
    /// - Throws: 노트 폴더에 파일이 없으면 `noteNotFound`.
    @discardableResult func scheduleUpdate(_ id: NoteID, _ mutate: (inout Note) -> Void) throws -> Note
    /// 미뤄 둔 변경을 지금 모두 쓴다. 창을 닫거나 앱을 끝낼 때 부른다.
    /// 하나가 실패해도 나머지를 계속 쓰고, 실패한 것은 남겨 둔 채 `pendingSavesFailed`를 던진다.
    func flushPendingSaves() throws
    /// 충돌(`conflict`)을 푼다. `.mine`은 저장소가 들고 있는 변경을 디스크 위에 쓰고,
    /// `.disk`는 그 변경을 버리고 디스크 내용을 받아들인다. 돌려주는 값은 푼 뒤의 노트.
    @discardableResult func resolveConflict(_ id: NoteID, keeping side: ConflictSide) throws -> Note

    /// 아직 디스크에 쓰지 않은 변경이 있는지. 저장 실패, 충돌, 없어진 파일 때문에 남은 것도 센다.
    func hasPendingChanges(_ id: NoteID) -> Bool
    /// 쓰지 않은 변경을 버린다. 알리지 않는다. 파일이 없어진 노트(`.removed`/`.external` 뒤에도
    /// 변경은 남아 있다)를 정리할 때 쓴다. 파일이 남아 있는 노트의 충돌은 `resolveConflict(_:keeping: .disk)`로 푼다.
    func discardPendingChanges(_ id: NoteID)

    /// 미뤄 둔 변경을 먼저 쓰고 휴지통으로 옮긴다. 그 쓰기가 실패하면 옮기지 않고 던진다.
    /// 휴지통에 같은 이름의 파일이 있으면 그 옛 파일을 `<id>-2.md`처럼 옆으로 옮겨 둘 다 남긴다.
    func moveToTrash(_ id: NoteID) throws
    /// 휴지통의 노트. 최근에 고친 것이 앞.
    func listTrash() throws -> NoteListing
    @discardableResult func restoreFromTrash(_ id: NoteID) throws -> Note
    /// 노트 파일을 휴지통을 거치지 않고 지운다. 미뤄 둔 변경은 버린다. 아무것도 적지 않은 빈 노트를
    /// 치울 때만 쓴다(되살릴 것이 없다). `.removed`(`.local`)로 알린다.
    /// - Throws: 노트 폴더에 파일이 없으면 `noteNotFound`.
    func delete(_ id: NoteID) throws

    /// 노트 폴더를 다시 훑어 다른 프로그램이 바꾼 것을 알린다. 앱이 앞으로 올 때 부른다.
    /// 폴더 감시는 파일이 생기고 없어지고 바꿔치기되는 것만 잡고, 제자리 수정은 이 호출이 잡는다.
    func refresh() throws
    /// 변경을 알려 받는다. 돌려받은 값을 들고 있는 동안만 알림이 온다.
    func observe(_ handler: @escaping @MainActor (StoreChange) -> Void) -> StoreObservation
}

/// 충돌을 풀 때 남길 쪽.
public enum ConflictSide: Hashable, Sendable {
    /// 이 앱에서 고친 내용. 디스크의 제목·스페이스·색·리마인더·본문을 덮어쓴다(모르는 머리 줄은 남긴다).
    case mine
    /// 디스크의 내용. 이 앱에서 고치고 아직 쓰지 못한 내용은 버린다.
    case disk
}
