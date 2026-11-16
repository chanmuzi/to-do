import AppKit

/// 메뉴 막대 아이콘(spec 4.3, 18.1): 겹친 노트 그림을 18pt 템플릿 이미지로 읽는다.
/// 파일은 `App/Resources/menubar-icon.pdf`(시안 묶음에서 복사한 것).
enum MenuBarIcon {
    nonisolated static let fileName = "menubar-icon.pdf"
    /// 캔버스 크기(pt). 그림 자체는 그 안에서 약 13pt 높이다.
    static let pointSize: CGFloat = 18

    struct NotFound: Error, CustomStringConvertible {
        var description: String { "메뉴 막대 아이콘 파일(\(MenuBarIcon.fileName))을 찾지 못했습니다" }
    }

    static func load() throws -> NSImage {
        guard let url = locate(), let image = NSImage(contentsOf: url) else { throw NotFound() }
        image.size = NSSize(width: pointSize, height: pointSize)
        image.isTemplate = true
        return image
    }

    /// `.app`으로 묶였을 때는 `Contents/Resources/`에서, `swift run`과 `swift test`에서는 SwiftPM 리소스 번들에서 찾는다.
    private static func locate() -> URL? {
        let fileManager = FileManager.default
        if let url = Bundle.main.resourceURL?.appendingPathComponent(fileName),
           fileManager.fileExists(atPath: url.path) {
            return url
        }
        // 앱 묶음 밖에서만 여기로 온다. Bundle.module은 번들이 없으면 멈추므로 위를 먼저 본다.
        if let url = Bundle.module.resourceURL?.appendingPathComponent(fileName),
           fileManager.fileExists(atPath: url.path) {
            return url
        }
        return nil
    }
}
