import Foundation

/// 폴더 안에서 파일이 생기거나 없어지거나 바꿔치기될 때 알려 준다.
/// 파일 내용을 제자리에서 고친 경우는 폴더가 바뀌지 않아 알림이 오지 않는다.
@MainActor
final class DirectoryWatcher {
    private let source: DispatchSourceFileSystemObject

    init?(directory: URL, onChange: @escaping @MainActor () -> Void) {
        let descriptor = open(directory.path, O_EVTONLY)
        guard descriptor >= 0 else { return nil }
        source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor, eventMask: [.write, .rename, .delete], queue: .main
        )
        source.setEventHandler {
            MainActor.assumeIsolated { onChange() }
        }
        source.setCancelHandler { close(descriptor) }
        source.resume()
    }

    func stop() {
        source.cancel()
    }
}
