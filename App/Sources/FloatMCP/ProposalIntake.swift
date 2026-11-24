import Darwin
import Foundation
import Models

struct IntakeFailure: LocalizedError {
    let errorDescription: String?
    init(_ message: String) { errorDescription = message }
}

final class ProposalIntake {
    @MainActor static let tool: Object = [
        "name": "propose_change", "description": "할 일, 리마인더, 일정 추가 또는 새 노트 만들기, 명시적으로 요청한 지침 변경을 제안합니다.",
        "inputSchema": ["type": "object", "additionalProperties": false,
                        "required": ["kind"], "properties": [
                            "kind": ["type": "string", "enum": ProposalArguments.Kind.allCases.map(\.rawValue)],
                            "note_id": ["type": "string", "description": "목록의 노트 ID. 새 노트에서는 선택한 출처"],
                            "lines": ["type": "array", "minItems": 1, "maxItems": 32, "items": ["type": "string"]],
                            "before": ["type": "string"], "after": ["type": "string"], "user_message": ["type": "string"],
                            "title": ["type": "string"], "markdown": ["type": "string"], "space_id": ["type": "string"],
                            "date_only": ["type": "boolean"], "time_zone": ["type": "string", "description": "IANA 시간대"],
                            "start": ["type": "string", "description": "현지 yyyy-MM-dd 또는 yyyy-MM-dd'T'HH:mm:ss"],
                            "end": ["type": "string", "description": "일정의 배타적 끝. 시작과 같은 형식"]
                        ], "oneOf": [
                            variant(.instructions, ["before", "after", "user_message"]),
                            variant(.todos, ["note_id", "lines"]), variant(.newNote, ["title", "markdown"]),
                            variant(.reminder, ["note_id", "title", "date_only", "time_zone", "start"]),
                            variant(.event, ["note_id", "title", "date_only", "time_zone", "start", "end"])
                        ]]
    ]
    private static func variant(_ kind: ProposalArguments.Kind, _ required: [String]) -> Object {
        let allowed = Set(required + ["kind"] + (kind == .newNote ? ["note_id", "space_id"] : []))
        return ["properties": ["kind": ["const": kind.rawValue]], "required": required,
                "propertyNames": ["enum": allowed.sorted()]]
    }
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

    func noteContext() throws -> AgentNoteContext? {
        let fd = openat(directory, AgentNoteContext.filename, O_RDONLY | O_NONBLOCK | O_NOFOLLOW | O_CLOEXEC)
        if fd < 0 && errno == ENOENT { return nil }
        guard fd >= 0 else { throw IntakeFailure("노트 상태를 열 수 없습니다.") }
        let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        var info = stat()
        guard fstat(fd, &info) == 0, info.st_mode & S_IFMT == S_IFREG, info.st_uid == getuid(),
              info.st_mode & 0o777 == 0o400 else { throw IntakeFailure("노트 상태 파일 권한을 확인해 주세요.") }
        return try JSONDecoder().decode(AgentNoteContext.self, from: handle.readToEnd() ?? Data())
    }

    func receive(_ arguments: Object, notes: NoteDirectory) throws -> String {
        let raw = try JSONSerialization.data(withJSONObject: arguments)
        guard raw.count <= 224 * 1024,
              let input = try? JSONDecoder().decode(ProposalArguments.self, from: raw),
              Set(arguments.keys).isSubset(of: input.fields),
              !arguments.values.contains(where: { $0 is NSNull }) else { throw IntakeFailure("제안 종류와 인자를 확인해 주세요.") }
        _ = try input.content()
        if input.kind == .instructions {
            let fd = openat(directory, InstructionEvidence.filename, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
            guard fd >= 0 else { throw IntakeFailure("이번 실행의 근거 메시지와 지침을 확인할 수 없습니다.") }
            let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
            guard let data = try? handle.readToEnd(),
                  let context = try? JSONDecoder().decode(InstructionEvidence.self, from: data) else {
                throw IntakeFailure("이번 실행의 접수 정보를 읽을 수 없습니다.")
            }
            try context.validate(input)
        }
        let version = try input.note_id.map { id in
            let name = id + ".md"
            guard try notes.list().contains(name) else { throw IntakeFailure("대상이 읽을 수 있는 노트 목록에 없습니다.") }
            return try TodoSubmission.fingerprint(Data(notes.read(name).utf8))
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(ProposalSubmission(arguments: input, version: input.before.map { TodoSubmission.fingerprint(Data($0.utf8)) } ?? version))
        let temporary = "." + UUID().uuidString
        let fd = openat(directory, temporary, O_CREAT | O_EXCL | O_WRONLY | O_CLOEXEC, 0o600)
        guard fd >= 0 else { throw IntakeFailure("접수 파일을 만들 수 없습니다.") }
        defer { unlinkat(directory, temporary, 0) }
        let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        try handle.write(contentsOf: data)
        try handle.close()
        // 동일 실행의 같은 대상과 줄은 최초 접수 시점의 기반 버전을 유지한다.
        let key = try TodoSubmission.fingerprint(encoder.encode(input)) + ".json"
        guard linkat(directory, temporary, directory, key, 0) == 0 || errno == EEXIST else {
            throw IntakeFailure("제안을 접수하지 못했습니다.")
        }
        return "검토할 제안을 접수했습니다."
    }
}
