import AppKit
import Store

/// 끝내기 전에 저장하지 못한 노트가 있을 때 띄우는 알림.
enum UnsavedNotesAlert {
    /// 저장하지 못한 노트를 알리고 그래도 끝낼지 묻는다. 끝내기를 고르면 `true`.
    static func confirmQuit(after error: Error) -> Bool {
        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = "저장하지 못한 노트가 있습니다"
        alert.informativeText = message(for: error)
        alert.addButton(withTitle: "돌아가기")
        alert.addButton(withTitle: "저장하지 않고 끝내기")
        return alert.runModal() == .alertSecondButtonReturn
    }

    /// 노트마다 한 줄씩 제목과 까닭을 적는다.
    static func message(for error: Error) -> String {
        guard case StoreError.pendingSavesFailed(let failures) = error else { return "\(error)" }
        let lines = failures.map { failure in
            let title = failure.title.isEmpty ? "제목 없음 (\(failure.id.rawValue.prefix(8)))" : failure.title
            return "• \(title): \(reason(failure.error))"
        }
        return (["지금 끝내면 아래 노트에서 고친 내용이 사라집니다."] + lines).joined(separator: "\n")
    }

    private static func reason(_ error: StoreError) -> String {
        switch error {
        case .conflict: "다른 프로그램이 파일을 고쳤습니다"
        case .noteNotFound: "노트 파일이 없어졌습니다"
        default: "\(error)"
        }
    }
}
