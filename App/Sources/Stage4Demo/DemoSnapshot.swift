import AppKit

/// 창의 내용을 이 프로세스 안에서 PNG로 그려 낸다. 화면 녹화 권한이 필요 없고 다른 창이 찍히지 않는다.
///
/// 뷰의 레이어 나무를 그대로 그린다(`cacheDisplay`는 둥근 모서리 밖을 흰색으로 채워 투명한 곳을 알 수 없다).
/// 창 그림자, 뒤 배경 흐림, 시스템 입력 커서는 찍히지 않는다. 반투명한 바탕이 보이도록 벽 색 위에 얹는다.
enum DemoSnapshot {
    /// 창 둘레에 두는 벽의 너비.
    static let margin: CGFloat = 24

    enum Failure: Error {
        case noContent, encoding
    }

    static func write(window: NSWindow, wall: NSColor, to path: String) throws {
        guard let view = window.contentView, let layer = view.layer else { throw Failure.noContent }
        view.layoutSubtreeIfNeeded()
        view.displayIfNeeded()

        let scale = window.backingScaleFactor
        let size = NSSize(width: view.bounds.width + margin * 2, height: view.bounds.height + margin * 2)
        guard let canvas = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale), pixelsHigh: Int(size.height * scale),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ) else { throw Failure.encoding }
        // 점 크기를 먼저 정해야 그리기 좌표가 점 단위가 된다.
        canvas.size = size
        guard let context = NSGraphicsContext(bitmapImageRep: canvas) else { throw Failure.encoding }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        view.effectiveAppearance.performAsCurrentDrawingAppearance {
            wall.setFill()
            NSRect(origin: .zero, size: size).fill()
        }
        // 내용 뷰는 위가 0인 좌표를 쓴다. 뒤집어 그린다.
        context.cgContext.translateBy(x: margin, y: margin + view.bounds.height)
        context.cgContext.scaleBy(x: 1, y: -1)
        layer.render(in: context.cgContext)
        NSGraphicsContext.restoreGraphicsState()

        guard let data = canvas.representation(using: .png, properties: [:]) else { throw Failure.encoding }
        try data.write(to: URL(fileURLWithPath: path))
    }
}
