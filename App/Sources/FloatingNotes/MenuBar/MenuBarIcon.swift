import AppKit
import Theme

/// 메뉴 막대 아이콘(spec 4.3, 18.1): C2 체크 카드 그림을 18pt 템플릿 이미지로 읽는다.
/// 파일은 `App/Resources/menubar-icon.pdf`(generate-brand-icons.swift로 생성).
enum MenuBarIcon {
    nonisolated static let fileName = "menubar-icon.pdf"
    /// 캔버스 크기(pt). 그림 자체는 그 안에서 약 13pt 높이다.


    struct NotFound: Error, CustomStringConvertible {
        var description: String { "메뉴 막대 아이콘 파일(\(MenuBarIcon.fileName))을 찾지 못했습니다" }
    }

    static func load() throws -> NSImage {
        guard let url = locate(), let image = NSImage(contentsOf: url) else { throw NotFound() }
        let pointSize = try ThemeTokens.bundled().component(.menubarIcon)
        image.size = NSSize(width: pointSize, height: pointSize)
        let cropped = trimmingHorizontalTransparency(image)
        cropped.isTemplate = true
        return cropped
    }

    /// 그림 배율과 세로 캔버스는 그대로 두고 투명한 좌우 열만 뺀다. NSStatusItem이 시스템 여백을 붙인다.
    static func trimmingHorizontalTransparency(_ source: NSImage) -> NSImage {
        var proposed = NSRect(origin: .zero, size: source.size)
        guard let cg = source.cgImage(forProposedRect: &proposed, context: nil, hints: nil) else { return source }
        let bitmap = NSBitmapImageRep(cgImage: cg)
        let columns = (0..<bitmap.pixelsWide).filter { x in
            (0..<bitmap.pixelsHigh).contains { y in (bitmap.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0 }
        }
        guard let first = columns.first, let last = columns.last else { return source }
        let scale = source.size.width / CGFloat(bitmap.pixelsWide)
        let rect = NSRect(x: CGFloat(first) * scale, y: 0,
                          width: CGFloat(last - first + 1) * scale, height: source.size.height)
        return NSImage(size: rect.size, flipped: false) { destination in
            source.draw(in: destination, from: rect, operation: .sourceOver, fraction: 1)
            return true
        }
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
