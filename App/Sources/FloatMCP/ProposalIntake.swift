import Darwin
import Foundation
import Models

struct IntakeFailure: LocalizedError {
    let errorDescription: String?
    init(_ message: String) { errorDescription = message }
}

final class ProposalIntake {
    @MainActor static let tool: Object = [
        "name": "propose_change", "description": "목록에 있는 노트에 할 일 추가를 제안합니다.",
        "inputSchema": ["type": "object", "additionalProperties": false,
                        "required": ["kind", "note_id", "lines"], "properties": [
                            "kind": ["type": "string", "enum": ["add_todos"]],
                            "note_id": ["type": "string", "description": "목록 파일 이름에서 마지막 .md를 뺀 값"],
                            "lines": ["type": "array", "minItems": 1, "maxItems": 32, "items": ["type": "string"]]
                        ]]
    ]
    private let directory: Int32

    init(path: String) throws {
        let fd = open(path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        var info = stat()
        guard fd >= 0 else { throw IntakeFailure("접수 폴더를 열 수 없습니다.") }
        guard fstat(fd, &info) == 0, info.st_uid == getuid(), info.st_mode & 0o777 == 0o700 else {
            close(fd)
            throw IntakeFailure("접수 폴더 권한이 올바르지 않습니다.")
        }
        directory = fd
    }

    deinit { close(directory) }

    func receive(_ arguments: Object, notes: NoteDirectory) throws -> String {
        guard arguments["kind"] as? String == "add_todos" else { throw IntakeFailure("지원하지 않는 제안 종류입니다.") }
        guard arguments.count == 3, let id = arguments["note_id"] as? String,
              let lines = arguments["lines"] as? [String], TodoSubmission.valid(lines: lines)
        else { throw IntakeFailure("할 일은 한 줄에 1024바이트까지, 1개에서 32개까지 제안할 수 있습니다.") }
        let name = id + ".md"
        guard try notes.list().contains(name) else { throw IntakeFailure("대상이 읽을 수 있는 노트 목록에 없습니다.") }
        let version = try TodoSubmission.fingerprint(Data(notes.read(name).utf8))
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let submission = TodoSubmission(noteID: id, lines: lines, version: version)
        let data = try encoder.encode(submission)
        let temporary = "." + UUID().uuidString
        let fd = openat(directory, temporary, O_CREAT | O_EXCL | O_WRONLY | O_CLOEXEC, 0o600)
        guard fd >= 0 else { throw IntakeFailure("접수 파일을 만들 수 없습니다.") }
        defer { unlinkat(directory, temporary, 0) }
        let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        try handle.write(contentsOf: data)
        try handle.close()
        // 동일 실행의 같은 대상과 줄은 최초 접수 시점의 기반 버전을 유지한다.
        let key = try TodoSubmission.fingerprint(encoder.encode([id] + lines)) + ".json"
        guard linkat(directory, temporary, directory, key, 0) == 0 || errno == EEXIST else {
            throw IntakeFailure("제안을 접수하지 못했습니다.")
        }
        return "검토할 제안을 접수했습니다."
    }
}
