import AppKit

/// 사용자가 시킨 일(새 노트, 노트 열기)을 하지 못했을 때 띄우는 알림.
enum RouteFailureAlert {
    static func present(title: String, error: Error) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = title
        alert.informativeText = "\(error)"
        alert.addButton(withTitle: "확인")
        // 노트 창은 앱을 앞으로 가져오지 않는다. 알림이 다른 앱 뒤에 묻히지 않게 앞으로 가져온다.
        NSApplication.shared.activate()
        alert.runModal()
    }
}
