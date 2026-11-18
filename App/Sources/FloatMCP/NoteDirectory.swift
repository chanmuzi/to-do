import Darwin
import Foundation

/// 열린 디렉터리를 기준으로 읽는다. 목록을 만든 뒤 파일이 링크로 교체돼도 따라가지 않는다.
final class NoteDirectory {
    private let descriptor: Int32
    private let url: URL

    init(path: String) throws {
        url = URL(fileURLWithPath: path, isDirectory: true)
        descriptor = open(path, O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW)
        guard descriptor >= 0 else { throw CocoaError(.fileReadNoSuchFile) }
    }

    deinit { close(descriptor) }

    func list() throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: url.path).filter { name in
            guard valid(name) else { return false }
            var info = stat()
            return fstatat(descriptor, name, &info, AT_SYMLINK_NOFOLLOW) == 0
                && (info.st_mode & S_IFMT) == S_IFREG
        }.sorted()
    }

    func read(_ name: String) throws -> String {
        guard valid(name) else { throw CocoaError(.fileReadInvalidFileName) }
        let fd = openat(descriptor, name, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        guard fd >= 0 else { throw CocoaError(.fileReadNoSuchFile) }
        let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        var info = stat()
        guard fstat(fd, &info) == 0, (info.st_mode & S_IFMT) == S_IFREG,
              let text = String(validating: try handle.readToEnd() ?? Data(), as: UTF8.self)
        else { throw CocoaError(.fileReadCorruptFile) }
        return text
    }

    private func valid(_ name: String) -> Bool {
        name.hasSuffix(".md") && !name.hasPrefix(".") && !name.contains("/") && !name.utf8.contains(0)
    }
}
