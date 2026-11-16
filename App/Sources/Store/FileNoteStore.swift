import Foundation
import Models

/// 노트 하나를 Markdown 파일 하나로 두는 저장소(D-003). 파일 표기는 `NoteFileCodec`.
@MainActor
public final class FileNoteStore: NoteStoring {
    public let location: StoreLocation

    private let autosaveDelay: Duration
    private let fileManager = FileManager.default
    private var handlers: [UUID: @MainActor (StoreChange) -> Void] = [:]
    private var pendingSaves: [NoteID: (note: Note, task: Task<Void, Never>)] = [:]
    /// 마지막으로 본 노트 폴더의 모습(노트 → 수정 시각). 바깥에서 바뀐 것을 가려내는 데 쓴다.
    private var snapshot: [NoteID: Date] = [:]
    private var watcher: DirectoryWatcher?

    /// 폴더가 없으면 만든다.
    /// - Parameter autosaveDelay: `scheduleSave`가 기다리는 시간.
    public init(location: StoreLocation, autosaveDelay: Duration = .milliseconds(500)) throws {
        self.location = location
        self.autosaveDelay = autosaveDelay
        try fileManager.createDirectory(at: location.notesDirectory, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: location.trashDirectory, withIntermediateDirectories: true)
        snapshot = try scan()
        watcher = DirectoryWatcher(directory: location.notesDirectory) { [weak self] in
            self?.refreshReportingFailure()
        }
    }

    // MARK: - 읽기

    public func list() throws -> [Note] {
        try notes(in: location.notesDirectory)
    }

    public func load(_ id: NoteID) throws -> Note {
        try read(id, in: location.notesDirectory)
    }

    public func listTrash() throws -> [Note] {
        try notes(in: location.trashDirectory)
    }

    // MARK: - 쓰기

    public func create(_ draft: NoteDraft) throws -> Note {
        let id = NoteID.make()
        let now = NoteFileCodec.truncatedToSeconds(Date())
        let note = Note(
            id: id, title: draft.title, body: draft.body, spaceID: draft.spaceID, colorID: draft.colorID,
            reminder: draft.reminder.map(NoteFileCodec.truncatedToSeconds), created: now, modified: now
        )
        guard !fileManager.fileExists(atPath: fileURL(id, in: location.notesDirectory).path) else {
            throw StoreError.noteAlreadyExists(id)
        }
        let saved = try write(note)
        emit(StoreChange(id: id, kind: .created, origin: .local))
        return saved
    }

    @discardableResult
    public func save(_ note: Note) throws -> Note {
        cancelPendingSave(note.id)
        let existed = fileManager.fileExists(atPath: fileURL(note.id, in: location.notesDirectory).path)
        let before = snapshot[note.id]
        let saved = try write(note)
        if !existed {
            emit(StoreChange(id: note.id, kind: .created, origin: .local))
        } else if saved.modified != before {
            emit(StoreChange(id: note.id, kind: .updated, origin: .local))
        }
        return saved
    }

    public func scheduleSave(_ note: Note) {
        cancelPendingSave(note.id)
        let delay = autosaveDelay
        let task = Task { [weak self] in
            guard (try? await Task.sleep(for: delay)) != nil else { return }
            self?.runPendingSave(note.id)
        }
        pendingSaves[note.id] = (note, task)
    }

    public func flushPendingSaves() throws {
        let pending = pendingSaves.values.map(\.note)
        for note in pending { try save(note) }
    }

    public func moveToTrash(_ id: NoteID) throws {
        cancelPendingSave(id)
        let source = fileURL(id, in: location.notesDirectory)
        guard fileManager.fileExists(atPath: source.path) else { throw StoreError.noteNotFound(id) }
        try fileManager.moveItem(at: source, to: fileURL(id, in: location.trashDirectory))
        snapshot[id] = nil
        emit(StoreChange(id: id, kind: .removed, origin: .local))
    }

    @discardableResult
    public func restoreFromTrash(_ id: NoteID) throws -> Note {
        let source = fileURL(id, in: location.trashDirectory)
        guard fileManager.fileExists(atPath: source.path) else { throw StoreError.noteNotFound(id) }
        let destination = fileURL(id, in: location.notesDirectory)
        guard !fileManager.fileExists(atPath: destination.path) else { throw StoreError.noteAlreadyExists(id) }
        try fileManager.moveItem(at: source, to: destination)
        let note = try load(id)
        snapshot[id] = note.modified
        emit(StoreChange(id: id, kind: .created, origin: .local))
        return note
    }

    // MARK: - 변경 알림

    public func observe(_ handler: @escaping @MainActor (StoreChange) -> Void) -> StoreObservation {
        let token = UUID()
        handlers[token] = handler
        return StoreObservation { [weak self] in self?.handlers[token] = nil }
    }

    /// 노트 폴더를 다시 훑어 바깥에서 바뀐 것을 알린다. 폴더 감시가 놓치는 경우
    /// (파일 내용을 제자리에서 고침)를 위해 앱이 앞으로 올 때 등에 부른다.
    public func refresh() throws {
        let current = try scan()
        let previous = snapshot
        snapshot = current
        for (id, modified) in current {
            if let old = previous[id] {
                if old != modified { emit(StoreChange(id: id, kind: .updated, origin: .external)) }
            } else {
                emit(StoreChange(id: id, kind: .created, origin: .external))
            }
        }
        for id in previous.keys where current[id] == nil {
            emit(StoreChange(id: id, kind: .removed, origin: .external))
        }
    }

    // MARK: - 내부

    private func refreshReportingFailure() {
        do {
            try refresh()
        } catch {
            FileHandle.standardError.write(Data("FileNoteStore: 노트 폴더를 다시 읽지 못했습니다: \(error)\n".utf8))
        }
    }

    private func runPendingSave(_ id: NoteID) {
        guard let pending = pendingSaves[id] else { return }
        do {
            try save(pending.note)
        } catch {
            pendingSaves[id] = nil
            emit(StoreChange(id: id, kind: .saveFailed(message: "\(error)"), origin: .local))
        }
    }

    private func cancelPendingSave(_ id: NoteID) {
        pendingSaves[id]?.task.cancel()
        pendingSaves[id] = nil
    }

    private func emit(_ change: StoreChange) {
        for handler in Array(handlers.values) { handler(change) }
    }

    private func fileURL(_ id: NoteID, in directory: URL) -> URL {
        directory.appendingPathComponent(id.rawValue).appendingPathExtension("md")
    }

    private func noteFiles(in directory: URL) throws -> [URL] {
        try fileManager
            .contentsOfDirectory(at: directory, includingPropertiesForKeys: [.contentModificationDateKey])
            .filter { $0.pathExtension == "md" && !$0.lastPathComponent.hasPrefix(".") }
    }

    private func modificationDate(_ url: URL) throws -> Date {
        let attributes = try fileManager.attributesOfItem(atPath: url.path)
        return attributes[.modificationDate] as? Date ?? Date()
    }

    private func scan() throws -> [NoteID: Date] {
        var result: [NoteID: Date] = [:]
        for url in try noteFiles(in: location.notesDirectory) {
            result[NoteID(rawValue: url.deletingPathExtension().lastPathComponent)] = try modificationDate(url)
        }
        return result
    }

    private func notes(in directory: URL) throws -> [Note] {
        try noteFiles(in: directory)
            .map { try read(NoteID(rawValue: $0.deletingPathExtension().lastPathComponent), in: directory) }
            .sorted { ($0.modified, $0.id.rawValue) > ($1.modified, $1.id.rawValue) }
    }

    private func readText(_ url: URL) throws -> String {
        let data = try Data(contentsOf: url)
        guard let text = String(data: data, encoding: .utf8) else { throw StoreError.unreadableFile(url) }
        return text
    }

    private func read(_ id: NoteID, in directory: URL) throws -> Note {
        let url = fileURL(id, in: directory)
        guard fileManager.fileExists(atPath: url.path) else { throw StoreError.noteNotFound(id) }
        let content = NoteFileCodec.decode(try readText(url))
        let modified = try modificationDate(url)
        let attributes = try fileManager.attributesOfItem(atPath: url.path)
        return Note(
            id: id, title: content.title, body: content.body, spaceID: content.spaceID,
            colorID: content.colorID, reminder: content.reminder,
            created: content.created ?? (attributes[.creationDate] as? Date) ?? modified,
            modified: modified
        )
    }

    /// 파일로 쓰고 수정 시각을 채워 돌려준다. 디스크의 내용과 같으면 쓰지 않는다.
    private func write(_ note: Note) throws -> Note {
        let url = fileURL(note.id, in: location.notesDirectory)
        let existing = fileManager.fileExists(atPath: url.path) ? try readText(url) : nil
        let text = NoteFileCodec.encode(NoteFileContent(
            title: note.title, spaceID: note.spaceID, colorID: note.colorID,
            reminder: note.reminder, created: note.created,
            unknownLines: existing.map { NoteFileCodec.decode($0).unknownLines } ?? [],
            body: note.body
        ))
        if text != existing {
            try Data(text.utf8).write(to: url, options: .atomic)
        }
        let modified = try modificationDate(url)
        snapshot[note.id] = modified
        var saved = note
        saved.modified = modified
        return saved
    }
}
