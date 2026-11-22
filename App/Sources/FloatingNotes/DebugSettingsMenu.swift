#if DEBUG
import AppKit
import Theme

/// 실제 버튼을 열어 자식 창의 내용과 화면 좌표를 기록한다.
enum DebugSettingsMenu {
    static func capture(at anchor: NSButton, to url: URL, image: Bool) {
        guard let parent = anchor.window else { return }
        let before = Set((parent.childWindows ?? []).map(ObjectIdentifier.init))
        anchor.sendAction(anchor.action, to: anchor.target)
        guard let popup = parent.childWindows?.first(where: { !before.contains(ObjectIdentifier($0)) && $0.isVisible }),
              let view = popup.contentView else {
            AppLog.warning("설정 값 메뉴 창이 열리지 않았어요")
            return
        }
        defer { popup.close() }
        view.layoutSubtreeIfNeeded()
        do {
            let button = parent.convertToScreen(anchor.convert(anchor.bounds, to: nil))
            struct Row: Encodable {
                let title: String
                let frame: CGRect
                let font: String
                let size: CGFloat
            }
            func rows(in node: NSView) -> [Row] {
                if let row = node as? PickerMenuRow {
                    return [Row(title: row.accessibilityLabel() ?? "", frame: row.convert(row.bounds, to: view),
                                font: row.textFont.fontName, size: row.textFont.pointSize)]
                }
                return node.subviews.flatMap { rows(in: $0) }
            }
            struct Layout: Encodable {
                let button: CGRect
                let popup: CGRect
                let shadow: Bool
                let rows: [Row]
            }
            let layout = Layout(button: button, popup: popup.frame, shadow: popup.hasShadow, rows: rows(in: view))
            let layoutURL = image ? url.deletingPathExtension().appendingPathExtension("json") : url
            try JSONEncoder().encode(layout).write(to: layoutURL, options: .atomic)
            if image {
                popup.displayIfNeeded()
                guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { throw CocoaError(.fileWriteUnknown) }
                view.cacheDisplay(in: view.bounds, to: rep)
                guard let data = rep.representation(using: .png, properties: [:]) else { throw CocoaError(.fileWriteUnknown) }
                try data.write(to: url, options: .atomic)
            }
        } catch { AppLog.warning("설정 값 메뉴 저장 실패: \(error)") }
    }
}
#endif
