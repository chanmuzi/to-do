import AppKit
import CoreText

/// 짧은 메뉴 글자를 대문자 높이로 가운데 놓고, 긴 값은 주어진 너비에서 줄인다.
enum MenuText {
    static func draw(_ text: String, font: NSFont, color: NSColor, x: CGFloat, width: CGFloat, center: CGFloat, flipped: Bool) {
        guard width > 0, let context = NSGraphicsContext.current?.cgContext else { return }
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes))
        let ellipsis = CTLineCreateWithAttributedString(NSAttributedString(string: "…", attributes: attributes))
        guard let visible = CTLineCreateTruncatedLine(line, width, .end, ellipsis) else { return }
        context.saveGState()
        defer { context.restoreGState() }
        context.translateBy(x: x, y: center)
        if flipped { context.scaleBy(x: 1, y: -1) }
        context.textMatrix = .identity
        context.textPosition = CGPoint(x: 0, y: -font.capHeight / 2)
        CTLineDraw(visible, context)
    }
}
