import Foundation
import Models

/// 노트 하나를 Markdown 파일 하나로 두는 저장소(D-003). 파일 표기는 `NoteFileCodec`.
///
/// ## 지금 값
/// 노트의 지금 값은 이 저장소가 들고 있다. `update`/`scheduleUpdate`는 디스크의 값에
/// 아직 쓰지 않은 변경을 얹은 값 위에 클로저를 적용한다.
///
/// ## 다른 프로그램이 고친 파일(충돌)
/// 노트마다 "저장소가 마지막으로 내준 글"을 기억한다(`load`, `create`, `restoreFromTrash`,
/// 쓰기 성공, `resolveConflict`가 갱신한다. `list`와 `refresh`는 갱신하지 않는다).
/// 쓰기 직전에 디스크의 글이 이것과 다르면 쓰지 않고 `StoreError.conflict`를 낸다.
/// 수정 시각이 아니라 글 전체를 견주므로 시각만 바뀐 파일은 충돌이 아니다.
@MainActor
public final class FileNoteStore: NoteStoring {
    public let location: StoreLocation

    private let autosaveDelay: Duration
    private let autosaveMaxWait: Duration
    private let files: NoteFiles
    private var handlers: [UUID: @MainActor (StoreChange) -> Void] = [:]
    /// 아직 디스크에 쓰지 않은 변경.
    private var pending: [NoteID: PendingSave] = [:]
    /// 노트마다 저장소가 마지막으로 내준(읽어 주거나 쓴) 파일의 글. 충돌 판정의 기준이다.
    private var known: [NoteID: String] = [:]
    /// 마지막으로 본 노트 폴더의 모습. 바깥에서 바뀐 것을 가려내는 데 쓴다.
    private var snapshot: [NoteID: FileStamp] = [:]
    private var watcher: DirectoryWatcher?

    private struct PendingSave {
        var note: Note
        /// 이 변경 묶음이 시작된 때. 자동 저장의 최대 대기를 재는 기준이다.
        let since: ContinuousClock.Instant
        var task: Task<Void, Never>?
        /// 충돌이 났다. 풀 때까지 자동 저장을 다시 걸지 않는다.
        var isConflicted = false
    }

    /// 폴더가 없으면 만든다.
    /// - Parameters:
    ///   - autosaveDelay: `scheduleUpdate`가 마지막 변경 뒤에 기다리는 시간.
    ///   - autosaveMaxWait: 계속 고치는 중이어도 첫 변경 뒤 이 시간이 지나면 쓴다.
    public init(
        location: StoreLocation,
        autosaveDelay: Duration = .milliseconds(500),
        autosaveMaxWait: Duration = .seconds(3)
    ) throws {
        self.location = location
        self.autosaveDelay = autosaveDelay
        self.autosaveMaxWait = autosaveMaxWait
        // 기존 월별 보기의 경계를 첫 실행 때 고정해 이후에는 노트가 저절로 보관되지 않게 한다.
        let migration = JSONFile<Date>(url: location.stateDirectory.appendingPathComponent("archive-cutoff.json"))
        let cutoff: Date
        if let saved = try migration.load() {
            cutoff = saved
        } else {
            let today = Calendar.current.startOfDay(for: Date())
            cutoff = Calendar.current.date(byAdding: .day, value: -6, to: today)!
            try migration.save(cutoff)
        }
        files = NoteFiles(location: location, archiveCutoff: cutoff)
        try files.createDirectories()
        snapshot = try files.scan()
        watcher = DirectoryWatcher(directory: location.notesDirectory) { [weak self] in
            self?.refreshReportingFailure()
        }
    }

    // MARK: - 읽기

    public func list() throws -> NoteListing {
        try listing(in: location.notesDirectory, includingPending: true)
    }

    public func load(_ id: NoteID) throws -> Note {
        if let entry = pending[id] { return entry.note }
        let file = try files.read(id, in: location.notesDirectory)
        known[id] = file.text
        return file.note
    }

    public func listTrash() throws -> NoteListing {
        try listing(in: location.trashDirectory, includingPending: false)
    }

    // MARK: - 쓰기

    public func create(_ draft: NoteDraft) throws -> Note {
        let id = NoteID.make()
        guard !files.itemExists(id, in: location.notesDirectory) else {
            throw StoreError.noteAlreadyExists(id)
        }
        let now = NoteFileCodec.truncatedToSeconds(Date())
        let text = NoteFileCodec.encode(NoteFileContent(
            title: NoteTitle.singleLine(draft.title), spaceID: draft.spaceID, colorID: draft.colorID,
            reminder: draft.schedules?.map(\.start).min() ?? draft.reminder.map(NoteFileCodec.truncatedToSeconds), schedules: draft.schedules, created: now, body: draft.body
        ))
        try files.write(text, id)
        let file = try files.read(id, in: location.notesDirectory)
        known[id] = file.text
        snapshot[id] = file.stamp
        emit(StoreChange(id: id, kind: .created, origin: .local))
        return file.note
    }

    @discardableResult
    public func update(_ id: NoteID, _ mutate: (inout Note) -> Void) throws -> Note {
        let note = try stage(id, mutate)
        guard pending[id] != nil else { return note }
        return try commit(id)
    }

    @discardableResult
    public func scheduleUpdate(_ id: NoteID, _ mutate: (inout Note) -> Void) throws -> Note {
        let note = try stage(id, mutate)
        if let entry = pending[id], !entry.isConflicted { arm(id) }
        return note
    }

    public func flushPendingSaves() throws {
        var failures: [SaveFailure] = []
        for id in pending.keys.sorted(by: { $0.rawValue < $1.rawValue }) {
            let title = pending[id]?.note.title ?? ""
            do {
                try commit(id)
            } catch {
                failures.append(SaveFailure(id: id, title: title, error: error))
            }
        }
        if !failures.isEmpty { throw StoreError.pendingSavesFailed(failures) }
    }

    @discardableResult
    public func resolveConflict(_ id: NoteID, keeping side: ConflictSide) throws -> Note {
        switch side {
        case .disk:
            let file = try files.read(id, in: location.notesDirectory)
            discardPending(id)
            known[id] = file.text
            snapshot[id] = file.stamp
            // 이 노트를 보고 있는 다른 쪽도 디스크 내용을 다시 읽게 한다.
            emit(StoreChange(id: id, kind: .updated, origin: .external))
            return file.note
        case .mine:
            guard pending[id] != nil else { return try load(id) }
            known[id] = try files.readText(id, in: location.notesDirectory)
            pending[id]?.isConflicted = false
            return try commit(id)
        }
    }

    public func hasPendingChanges(_ id: NoteID) -> Bool {
        pending[id] != nil
    }

    public func discardPendingChanges(_ id: NoteID) {
        discardPending(id)
        if !files.noteExists(id, in: location.notesDirectory) { known[id] = nil }
    }

    public func moveToTrash(_ id: NoteID) throws {
        guard files.noteExists(id, in: location.notesDirectory) else { throw StoreError.noteNotFound(id) }
        // 미뤄 둔 변경을 먼저 쓴다. 못 쓰면 옮기지 않는다(휴지통의 노트가 옛 내용이 되지 않게).
        if pending[id] != nil { try commit(id) }
        try files.moveToTrash(id)
        known[id] = nil
        snapshot[id] = nil
        emit(StoreChange(id: id, kind: .removed, origin: .local))
    }

    public func delete(_ id: NoteID) throws {
        guard files.noteExists(id, in: location.notesDirectory) else { throw StoreError.noteNotFound(id) }
        // 이 앱이 모르는 머리 줄(다른 도구가 적은 태그 등)이 있으면 그 내용을 잃지 않게 휴지통으로 보낸다.
        let text = try files.readText(id, in: location.notesDirectory)
        if !NoteFileCodec.decode(text).unknownLines.isEmpty {
            try moveToTrash(id)
            return
        }
        try files.delete(id)
        discardPending(id)
        known[id] = nil
        snapshot[id] = nil
        emit(StoreChange(id: id, kind: .removed, origin: .local))
    }

    @discardableResult
    public func restoreFromTrash(_ id: NoteID) throws -> Note {
        guard files.noteExists(id, in: location.trashDirectory) else { throw StoreError.noteNotFound(id) }
        guard !files.itemExists(id, in: location.notesDirectory) else {
            throw StoreError.noteAlreadyExists(id)
        }
        try files.restoreFromTrash(id)
        let file = try files.read(id, in: location.notesDirectory)
        known[id] = file.text
        snapshot[id] = file.stamp
        emit(StoreChange(id: id, kind: .created, origin: .local))
        return file.note
    }

    // MARK: - 변경 알림

    public func observe(_ handler: @escaping @MainActor (StoreChange) -> Void) -> StoreObservation {
        let token = UUID()
        handlers[token] = handler
        return StoreObservation { [weak self] in self?.handlers[token] = nil }
    }

    public func refresh() throws {
        let current = try files.scan()
        let previous = snapshot
        snapshot = current
        for id in current.keys.sorted(by: { $0.rawValue < $1.rawValue }) {
            guard let old = previous[id] else {
                emit(StoreChange(id: id, kind: .created, origin: .external))
                continue
            }
            if old != current[id] {
                emit(StoreChange(id: id, kind: externalChangeKind(id), origin: .external))
            }
        }
        for id in previous.keys.sorted(by: { $0.rawValue < $1.rawValue }) where current[id] == nil {
            if pending[id] == nil { known[id] = nil }
            emit(StoreChange(id: id, kind: .removed, origin: .external))
        }
    }

    // MARK: - 지금 값과 쓰기

    /// 지금 값에 `mutate`를 적용해 쓰지 않은 변경으로 올려 둔다. 바뀐 것이 없으면 올리지 않는다.
    private func stage(_ id: NoteID, _ mutate: (inout Note) -> Void) throws(StoreError) -> Note {
        var entry: PendingSave
        if let existing = pending[id] {
            entry = existing
        } else {
            let file = try files.read(id, in: location.notesDirectory)
            if known[id] == nil { known[id] = file.text }
            entry = PendingSave(note: file.note, since: .now)
        }
        var note = entry.note
        mutate(&note)
        note.title = NoteTitle.singleLine(note.title)
        note.modified = entry.note.modified
        for index in note.schedules.indices {
            let previous = entry.note.schedules.first { $0.id == note.schedules[index].id }
            if previous?.start != note.schedules[index].start {
                note.schedules[index].start = NoteFileCodec.truncatedToSeconds(note.schedules[index].start)
            }
            if previous?.end != note.schedules[index].end {
                note.schedules[index].end = note.schedules[index].end.map(NoteFileCodec.truncatedToSeconds)
            }
        }
        guard note != entry.note || pending[id] != nil else { return note }
        entry.note = note
        pending[id] = entry
        return note
    }

    /// 쓰지 않은 변경을 디스크에 쓴다. 실패하면 변경을 남겨 둔 채 던진다.
    @discardableResult
    private func commit(_ id: NoteID) throws(StoreError) -> Note {
        guard let entry = pending[id] else { return try files.read(id, in: location.notesDirectory).note }
        entry.task?.cancel()
        pending[id]?.task = nil

        // 노트 폴더에 없는 노트는 파일을 만들지 않는다(여기서 noteNotFound).
        let diskText = try files.readText(id, in: location.notesDirectory)
        if let knownText = known[id], knownText != diskText {
            pending[id]?.isConflicted = true
            throw .conflict(id)
        }
        let note = entry.note
        // 본문만 고친 옛 파일에 새 필드를 강제로 넣거나 날짜 표기를 바꾸지 않는다.
        let diskContent = NoteFileCodec.decode(diskText)
        let oldSchedules = try files.read(id, in: location.notesDirectory).note.schedules
        let schedules = diskContent.schedules == nil && oldSchedules == note.schedules ? nil : note.schedules
        let text = NoteFileCodec.encode(
            NoteFileContent(
                title: note.title, spaceID: note.spaceID, colorID: note.colorID,
                reminder: note.reminder ?? note.schedules.map(\.start).min(), schedules: schedules,
                archived: note.isArchived == (note.created < files.archiveCutoff) && diskContent.archived == nil ? nil : note.isArchived,
                created: note.created, body: note.body
            ),
            over: diskText
        )
        if text != diskText { try files.write(text, id) }
        let stamp = try files.stamp(id, in: location.notesDirectory)
        pending[id] = nil
        known[id] = text
        snapshot[id] = stamp
        if text != diskText { emit(StoreChange(id: id, kind: .updated, origin: .local)) }
        var saved = note
        saved.modified = stamp.modified
        return saved
    }

    /// 자동 저장을 건다. 마지막 변경 뒤 `autosaveDelay`, 늦어도 첫 변경 뒤 `autosaveMaxWait`.
    private func arm(_ id: NoteID) {
        guard let entry = pending[id] else { return }
        entry.task?.cancel()
        let remaining = autosaveMaxWait - (ContinuousClock.now - entry.since)
        let delay = min(autosaveDelay, max(.zero, remaining))
        pending[id]?.task = Task { [weak self] in
            guard (try? await Task.sleep(for: delay)) != nil else { return }
            self?.runPendingSave(id)
        }
    }

    private func runPendingSave(_ id: NoteID) {
        guard pending[id] != nil else { return }
        do {
            try commit(id)
        } catch .conflict {
            emit(StoreChange(id: id, kind: .conflict, origin: .external))
        } catch .noteNotFound {
            // 쓰려는 사이에 파일이 없어졌다. 저장 실패가 아니라 없어진 것으로 알린다(변경은 남는다).
            // 폴더를 훑다가 이미 알렸으면 다시 알리지 않는다.
            guard snapshot[id] != nil else { return }
            snapshot[id] = nil
            emit(StoreChange(id: id, kind: .removed, origin: .external))
        } catch {
            emit(StoreChange(id: id, kind: .saveFailed(message: error.description), origin: .local))
        }
    }

    private func discardPending(_ id: NoteID) {
        pending[id]?.task?.cancel()
        pending[id] = nil
    }

    /// 바깥에서 바뀐 노트를 어떻게 알릴지. 쓰지 않은 변경이 있고 글이 달라졌으면 충돌이다.
    private func externalChangeKind(_ id: NoteID) -> StoreChange.Kind {
        guard pending[id] != nil,
              let text = try? files.readText(id, in: location.notesDirectory),
              text != known[id]
        else { return .updated }
        pending[id]?.task?.cancel()
        pending[id]?.task = nil
        pending[id]?.isConflicted = true
        return .conflict
    }

    // MARK: - 내부

    private func refreshReportingFailure() {
        do {
            try refresh()
        } catch {
            FileHandle.standardError.write(Data("FileNoteStore: 노트 폴더를 다시 읽지 못했습니다: \(error)\n".utf8))
        }
    }

    private func emit(_ change: StoreChange) {
        for handler in Array(handlers.values) { handler(change) }
    }

    private func listing(in directory: URL, includingPending: Bool) throws(StoreError) -> NoteListing {
        var notes: [Note] = []
        var failures: [NoteReadFailure] = []
        for url in try files.entries(in: directory) {
            let id = files.id(of: url)
            do {
                let file = try files.read(id, in: directory)
                notes.append(includingPending ? pending[id]?.note ?? file.note : file.note)
            } catch {
                failures.append(NoteReadFailure(id: id, url: files.url(id, in: directory), error: error))
            }
        }
        return NoteListing(
            notes: notes.sorted { ($0.modified, $0.id.rawValue) > ($1.modified, $1.id.rawValue) },
            failures: failures.sorted { $0.id.rawValue < $1.id.rawValue }
        )
    }
}
