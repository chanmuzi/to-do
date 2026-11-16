#if DEBUG
import Foundation

/// 확인용 명령 통로의 이번 실행분: 이번 실행에서만 통하는 표와, 명령이 파일을 쓸 수 있는 하나뿐인 폴더.
///
/// 분산 알림은 이 Mac의 어느 프로세스나 보낼 수 있다. 그래서 명령마다 표를 요구하고
/// (표는 켤 때 새로 만들어 출력 폴더의 `control-token`에 소유자만 읽게 적는다),
/// 명령이 쓰는 파일은 켤 때 받은 출력 폴더 바로 아래의 이름으로만 받는다.
struct DebugControlSession: Equatable {
    static let tokenFileName = "control-token"

    let token: String
    let outputDirectory: URL

    /// 출력 폴더를 만들고(없으면) 새 표를 적는다.
    static func start(in directory: URL) throws -> DebugControlSession {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let session = DebugControlSession(
            token: UUID().uuidString, outputDirectory: directory.standardizedFileURL
        )
        let tokenFile = session.outputDirectory.appendingPathComponent(tokenFileName)
        // 지난 실행의 표 파일(또는 그 자리에 놓인 링크)을 따라가 쓰지 않도록 지우고 새로 만든다.
        if (try? tokenFile.checkResourceIsReachable()) == true
            || (try? fileManager.destinationOfSymbolicLink(atPath: tokenFile.path)) != nil {
            try fileManager.removeItem(at: tokenFile)
        }
        guard fileManager.createFile(
            atPath: tokenFile.path, contents: Data(session.token.utf8),
            attributes: [.posixPermissions: 0o600]
        ) else {
            throw CocoaError(.fileWriteUnknown, userInfo: [NSFilePathErrorKey: tokenFile.path])
        }
        return session
    }

    /// 알림에 실려 온 글(`<표> <명령>`)에서 명령을 꺼낸다. 표가 맞지 않으면 `nil`.
    func command(from payload: String) -> String? {
        let parts = payload.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2, String(parts[0]) == token, !parts[1].isEmpty else { return nil }
        return String(parts[1])
    }

    /// 명령이 준 파일 이름을 출력 폴더 안의 경로로 바꾼다. 폴더를 벗어나는 이름(경로 구분자, `..`,
    /// 숨김 이름, 표 파일)은 받지 않는다.
    func outputURL(named name: String) -> URL? {
        guard !name.isEmpty, !name.hasPrefix("."), !name.contains("/"), !name.contains("\0"),
              name != Self.tokenFileName
        else { return nil }
        let url = outputDirectory.appendingPathComponent(name, isDirectory: false)
        // 그 이름이 폴더 밖을 가리키는 링크면 따라가지 않는다.
        guard (try? FileManager.default.destinationOfSymbolicLink(atPath: url.path)) == nil else { return nil }
        return url
    }
}
#endif
