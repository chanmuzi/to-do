import AppKit
import Testing
@testable import Editor

@MainActor @Suite struct IndentDecorationTests {
    @Test func ancestorMarginIsEmptyAndQuoteKeepsItsBar() throws {
        let h = try EditorHarness("- 부모\n\t- 자식\n\t\t[ ] 투두\n> 인용")
        let manager = h.controller.layoutManager
        manager.ensureLayout(for: manager.documentRange)
        var fragments: [MarkdownLayoutFragment] = []
        manager.enumerateTextLayoutFragments(from: manager.documentRange.location, options: [.ensuresLayout]) {
            if let fragment = $0 as? MarkdownLayoutFragment { fragments.append(fragment) }
            return true
        }
        try #require(fragments.count == 4)
        for index in [1, 2, 3] {
            let fragment = fragments[index]
            let width = 340
            let height = Int(ceil(fragment.layoutFragmentFrame.height))
            let context = try #require(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                                 bytesPerRow: width, space: CGColorSpaceCreateDeviceGray(),
                                                 bitmapInfo: CGImageAlphaInfo.none.rawValue))
            context.setFillColor(gray: 1, alpha: 1)
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
            context.translateBy(x: 0, y: CGFloat(height))
            context.scaleBy(x: 1, y: -1)
            fragment.draw(at: CGPoint(x: fragment.layoutFragmentFrame.minX, y: 0), in: context)
            let pixels = try #require(context.data).assumingMemoryBound(to: UInt8.self)
            let decoration = try #require(fragment.decoration)
            let margin = index == 3 ? Int(h.controller.style.gutter) : Int(decoration.gutterX)
            let ink = (0..<height).contains { y in (0..<margin).contains { x in pixels[y * context.bytesPerRow + x] < 250 } }
            #expect(ink == (index == 3))
        }
    }
}
