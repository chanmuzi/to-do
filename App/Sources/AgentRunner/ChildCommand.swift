import Darwin
import Foundation

public struct AgentCommand: Sendable {
    public let executable: URL
    public let arguments: [String]
    public let environment: [String: String]
    public let directory: URL
}

public enum AgentError: Error, Equatable, Sendable {
    case missingExecutable(String)
    case process(Int32)
    case timeout
    case invalidOutput
    case isolation(String)
    case failed(Int32)
    case loginExpired
    case providerFailure
    case unsupportedEngine
}

func onWorker<T: Sendable>(_ operation: @Sendable @escaping () throws -> T) async throws -> T {
    let worker = Task.detached(operation: operation)
    return try await withTaskCancellationHandler {
        try await worker.value
    } onCancel: {
        worker.cancel()
    }
}

private func withStrings<T>(_ strings: [String], _ body: (UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>) throws -> T) throws -> T {
    guard !strings.contains(where: { $0.utf8.contains(0) }) else { throw AgentError.process(EINVAL) }
    var pointers = [UnsafeMutablePointer<CChar>?]()
    defer { pointers.forEach { free($0) } }
    for string in strings {
        guard let copy = strdup(string) else { throw AgentError.process(ENOMEM) }
        pointers.append(copy)
    }
    pointers.append(nil)
    return try pointers.withUnsafeMutableBufferPointer { try body($0.baseAddress!) }
}

extension AgentCommand {
    /// 자식 전용 프로세스 그룹을 만든다. 기본 stdin은 닫혀 있다. 호출자의 환경, 열려 있는 파일은 물려주지 않는다.
    func execute(timeout: Duration, mergeDiagnostics: Bool = false, standardInput: FileHandle? = nil, line: (Data) throws -> Void) throws -> Int32 {
        func check(_ code: Int32) throws {
            guard code == 0 else { throw AgentError.process(code) }
        }
        try Task.checkCancellation()
        let output = Pipe()
        let reader = output.fileHandleForReading
        let writer = output.fileHandleForWriting
        var actions: posix_spawn_file_actions_t?
        var attributes: posix_spawnattr_t?
        try check(posix_spawn_file_actions_init(&actions))
        defer { posix_spawn_file_actions_destroy(&actions) }
        try check(posix_spawnattr_init(&attributes))
        defer { posix_spawnattr_destroy(&attributes) }
        try check(posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_SETPGROUP | POSIX_SPAWN_CLOEXEC_DEFAULT)))
        try check(posix_spawnattr_setpgroup(&attributes, 0))
        try check(posix_spawn_file_actions_addchdir(&actions, directory.path))
        if let standardInput {
            try check(posix_spawn_file_actions_adddup2(&actions, standardInput.fileDescriptor, STDIN_FILENO))
        } else {
            try check(posix_spawn_file_actions_addopen(&actions, STDIN_FILENO, "/dev/null", O_RDONLY, 0))
        }
        try check(posix_spawn_file_actions_adddup2(&actions, writer.fileDescriptor, STDOUT_FILENO))
        if mergeDiagnostics {
            try check(posix_spawn_file_actions_adddup2(&actions, writer.fileDescriptor, STDERR_FILENO))
        } else {
            try check(posix_spawn_file_actions_addopen(&actions, STDERR_FILENO, "/dev/null", O_WRONLY, 0))
        }
        var pid: pid_t = 0
        try withStrings([executable.path] + arguments) { argv in
            try withStrings(environment.map { "\($0.key)=\($0.value)" }) { env in
                try check(posix_spawn(&pid, executable.path, &actions, &attributes, argv, env))
            }
        }
        var reaped = false
        defer {
            if !reaped {
                kill(-pid, SIGKILL)
                while waitpid(pid, nil, 0) == -1 && errno == EINTR {}
            }
        }
        try writer.close()
        let deadline = ContinuousClock.now.advanced(by: timeout)
        var pending = Data()
        var buffer = [UInt8](repeating: 0, count: 16384)
        var eof = false
        while true {
            try Task.checkCancellation()
            guard ContinuousClock.now < deadline else { throw AgentError.timeout }
            if eof {
                var status: Int32 = 0
                let result = waitpid(pid, &status, WNOHANG)
                if result == pid {
                    reaped = true
                    let signal = status & 0x7f
                    return signal == 0 ? (status >> 8) & 0xff : 128 + signal
                }
                if result == -1 && errno != EINTR { throw AgentError.process(errno) }
                usleep(10_000)
                continue
            }
            var fd = pollfd(fd: reader.fileDescriptor, events: Int16(POLLIN), revents: 0)
            let ready = poll(&fd, 1, 40)
            if ready == -1 && errno != EINTR { throw AgentError.process(errno) }
            guard ready > 0 else { continue }
            let count = read(reader.fileDescriptor, &buffer, buffer.count)
            if count == -1 && errno == EINTR { continue }
            guard count >= 0 else { throw AgentError.process(errno) }
            if count == 0 {
                eof = true
                if !pending.isEmpty { try line(pending) }
            } else {
                var chunk = buffer[..<count]
                while let end = chunk.firstIndex(of: 10) {
                    pending.append(contentsOf: chunk[..<end])
                    if !pending.isEmpty { try line(pending) }
                    pending.removeAll(keepingCapacity: true)
                    chunk = chunk[(end + 1)...]
                }
                pending.append(contentsOf: chunk)
                guard pending.count <= 16 * 1024 * 1024 else { throw AgentError.invalidOutput }
            }
        }
    }

    /// 연결 화면에서 만든 로그인 명령의 종료를 기다린다. 출력에 포함될 수 있는 인증 정보는 보관하지 않는다.
    package func waitForLogin() async throws {
        try await onWorker {
            let status = try execute(timeout: .seconds(600)) { _ in }
            guard status == 0 else { throw AgentError.failed(status) }
        }
    }

    func capture(mergeDiagnostics: Bool = false, byteLimit: Int = 1024 * 1024) throws -> (Int32, Data) {
        var data = Data()
        let status = try execute(timeout: .seconds(10), mergeDiagnostics: mergeDiagnostics) {
            guard data.count + $0.count < byteLimit else { throw AgentError.invalidOutput }
            data.append($0)
            data.append(10)
        }
        return (status, data)
    }
}
