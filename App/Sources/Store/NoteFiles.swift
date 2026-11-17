import Foundation
import Models

/// 파일의 겉모습. 내용을 읽지 않고 바뀌었는지 가늠하는 데 쓴다.
struct FileStamp: Hashable {
    let modified: Date
    let size: Int
}

/// 디스크에서 읽은 노트 파일 하나.
struct NoteFile {
    let note: Note
    /// 파일의 글 전체(머리 포함).
    let text: String
    let stamp: FileStamp
}

/// 노트 폴더와 휴지통의 파일을 다룬다. 상태는 없고, 오류는 모두 `StoreError`로 바꿔 던진다.
struct NoteFiles {
    let location: StoreLocation
    private var fileManager: FileManager { .default }

    func createDirectories() throws {
        try fileManager.createDirectory(at: location.notesDirectory, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: location.trashDirectory, withIntermediateDirectories: true)
    }

    func url(_ id: NoteID, in directory: URL) -> URL {
        // 그 자리에 폴더가 있어도 URL 모양이 달라지지 않게 파일로 못박는다.
        directory.appendingPathComponent("\(id.rawValue).md", isDirectory: false)
    }

    func id(of url: URL) -> NoteID {
        NoteID(rawValue: url.deletingPathExtension().lastPathComponent)
    }

    /// 그 자리에 무엇이든 있다(폴더 포함).
    func itemExists(_ id: NoteID, in directory: URL) -> Bool {
        fileManager.fileExists(atPath: url(id, in: directory).path)
    }

    /// 그 자리에 보통 파일이 있다.
    func noteExists(_ id: NoteID, in directory: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return fileManager.fileExists(atPath: url(id, in: directory).path, isDirectory: &isDirectory)
            && !isDirectory.boolValue
    }

    // MARK: - 읽기

    /// 폴더 안의 `.md` 항목 전부(숨김 제외). `.md`로 끝나는 폴더도 들어 있다.
    func entries(in directory: URL) throws(StoreError) -> [URL] {
        do {
            return try fileManager
                .contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
                .filter { $0.pathExtension == "md" && !$0.lastPathComponent.hasPrefix(".") }
        } catch {
            throw .unreadableFile(directory)
        }
    }

    /// 노트 폴더의 노트 파일과 그 겉모습. 파일이 아닌 항목은 뺀다.
    func scan() throws(StoreError) -> [NoteID: FileStamp] {
        var result: [NoteID: FileStamp] = [:]
        for url in try entries(in: location.notesDirectory) {
            let id = id(of: url)
            guard noteExists(id, in: location.notesDirectory),
                  let stamp = try? stamp(id, in: location.notesDirectory)
            else { continue }
            result[id] = stamp
        }
        return result
    }

    func stamp(_ id: NoteID, in directory: URL) throws(StoreError) -> FileStamp {
        let url = url(id, in: directory)
        do {
            let attributes = try fileManager.attributesOfItem(atPath: url.path)
            return FileStamp(
                modified: attributes[.modificationDate] as? Date ?? Date(),
                size: (attributes[.size] as? NSNumber)?.intValue ?? 0
            )
        } catch {
            throw .unreadableFile(url)
        }
    }

    func readText(_ id: NoteID, in directory: URL) throws(StoreError) -> String {
        let url = url(id, in: directory)
        guard itemExists(id, in: directory) else { throw .noteNotFound(id) }
        guard noteExists(id, in: directory),
              let data = try? Data(contentsOf: url),
              // 바이트를 그대로 글로 옮긴다(맨 앞의 BOM도 글자로 남겨 다시 쓸 때 보존한다).
              let text = String(validating: data, as: UTF8.self)
        else { throw .unreadableFile(url) }
        return text
    }

    func read(_ id: NoteID, in directory: URL) throws(StoreError) -> NoteFile {
        let text = try readText(id, in: directory)
        let stamp = try stamp(id, in: directory)
        let content = NoteFileCodec.decode(text)
        let url = url(id, in: directory)
        let creation = (try? fileManager.attributesOfItem(atPath: url.path))?[.creationDate] as? Date
        let note = Note(
            id: id, title: content.title, body: content.body, spaceID: content.spaceID,
            colorID: content.colorID, reminder: content.reminder, schedules: content.schedules,
            // 머리에 만든 날짜가 없으면 파일의 날짜를 쓴다. 머리에 적을 때와 같게 초 아래를 버린다.
            created: content.created ?? NoteFileCodec.truncatedToSeconds(creation ?? stamp.modified),
            modified: stamp.modified
        )
        return NoteFile(note: note, text: text, stamp: stamp)
    }

    // MARK: - 쓰기

    /// 노트 폴더의 파일을 통째로 바꿔 쓴다.
    func write(_ text: String, _ id: NoteID) throws(StoreError) {
        do {
            try Data(text.utf8).write(to: url(id, in: location.notesDirectory), options: .atomic)
        } catch {
            throw .writeFailed(id, message: error.localizedDescription)
        }
    }

    /// 노트 폴더에서 휴지통으로 옮긴다. 휴지통에 같은 이름이 있으면 그 옛 파일을 먼저 옆으로 옮긴다.
    func moveToTrash(_ id: NoteID) throws(StoreError) {
        do {
            if itemExists(id, in: location.trashDirectory) {
                try fileManager.moveItem(at: url(id, in: location.trashDirectory), to: freeTrashURL(for: id))
            }
            try fileManager.moveItem(
                at: url(id, in: location.notesDirectory), to: url(id, in: location.trashDirectory)
            )
        } catch {
            throw .writeFailed(id, message: error.localizedDescription)
        }
    }

    /// 노트 폴더의 파일을 지운다(휴지통을 거치지 않는다).
    func delete(_ id: NoteID) throws(StoreError) {
        do {
            try fileManager.removeItem(at: url(id, in: location.notesDirectory))
        } catch {
            throw .writeFailed(id, message: error.localizedDescription)
        }
    }

    func restoreFromTrash(_ id: NoteID) throws(StoreError) {
        do {
            try fileManager.moveItem(
                at: url(id, in: location.trashDirectory), to: url(id, in: location.notesDirectory)
            )
        } catch {
            throw .writeFailed(id, message: error.localizedDescription)
        }
    }

    /// 휴지통에서 비어 있는 `<id>-2.md`, `<id>-3.md`, … 자리.
    private func freeTrashURL(for id: NoteID) -> URL {
        var suffix = 2
        while true {
            let candidate = NoteID(rawValue: "\(id.rawValue)-\(suffix)")
            if !itemExists(candidate, in: location.trashDirectory) {
                return url(candidate, in: location.trashDirectory)
            }
            suffix += 1
        }
    }
}
