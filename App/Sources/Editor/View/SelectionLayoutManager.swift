import AppKit
import Theme

/// TextKit의 선택 구간만 글자 경계로 바꾼다. 선택 데이터와 탐색은 시스템에 그대로 맡긴다.
nonisolated final class SelectionLayoutManager: NSTextLayoutManager {
    private struct Segment {
        let range: NSTextRange?
        let rect: CGRect
        let baseline: CGFloat
        let container: NSTextContainer
    }

    override func enumerateTextSegments(
        in textRange: NSTextRange, type: NSTextLayoutManager.SegmentType,
        options: NSTextLayoutManager.SegmentOptions,
        using block: (NSTextRange?, CGRect, CGFloat, NSTextContainer) -> Bool
    ) {
        guard type == .selection, !textRange.isEmpty else {
            super.enumerateTextSegments(in: textRange, type: type, options: options, using: block)
            return
        }
        for segment in selectionSegments(in: textRange) {
            if !block(options.contains(.rangeNotRequired) ? nil : segment.range,
                      segment.rect, segment.baseline, segment.container) { break }
        }
    }

    func selectionRects(in range: NSTextRange) -> [CGRect] {
        selectionSegments(in: range).map(\.rect)
    }

    private func selectionSegments(in range: NSTextRange) -> [Segment] {
        guard let contentStorage = textContentManager else { return [] }
        let base = contentStorage.documentRange.location
        let start = contentStorage.offset(from: base, to: range.location)
        let length = contentStorage.offset(from: range.location, to: range.endLocation)
        guard length > 0 else { return [] }
        let selections = [NSRange(location: start, length: length)]
        var segments: [Segment] = []
        let viewport = textViewportLayoutController.viewportRange ?? contentStorage.documentRange
        enumerateTextLayoutFragments(from: viewport.location, options: [.ensuresLayout]) { fragment in
            guard fragment.rangeInElement.location.compare(viewport.endLocation) != .orderedDescending,
                  let paragraph = fragment.textElement as? NSTextParagraph else { return false }
            let string = paragraph.attributedString
            let start = contentStorage.offset(from: base, to: fragment.rangeInElement.location)
            let frame = fragment.layoutFragmentFrame
            let decoration = (fragment as? MarkdownLayoutFragment)?.decoration
            guard decoration?.isCollapsed != true else { return true }
            let text = string.string as NSString
            for selected in selections {
                let intersection = NSIntersectionRange(selected, NSRange(location: start, length: string.length))
                guard intersection.length > 0 else { continue }
                let local = NSRange(location: intersection.location - start, length: intersection.length)
                string.enumerateAttributes(in: local) { attributes, run, _ in
                    guard let font = attributes[.font] as? NSFont,
                          font.pointSize > EditorMetrics.hiddenFontSize else { return }
                    for line in fragment.textLineFragments {
                        var part = NSIntersectionRange(run, line.characterRange)
                        // 줄바꿈과 빈 줄은 원문 선택에 포함하지만 그릴 글자가 없다.
                        while part.length > 0, (CharacterSet.newlines as NSCharacterSet).characterIsMember(text.character(at: NSMaxRange(part) - 1)) {
                            part.length -= 1
                        }
                        guard part.length > 0,
                              let lower = contentStorage.location(base, offsetBy: start + part.location),
                              let upper = contentStorage.location(lower, offsetBy: part.length),
                              let range = NSTextRange(location: lower, end: upper) else { continue }
                        let lineFont = decoration?.lineFont ?? font
                        let baseline = frame.minY + line.typographicBounds.midY + (lineFont.ascender + lineFont.descender) / 2
                        let rise = (attributes[.baselineOffset] as? NSNumber)?.doubleValue ?? 0
                        self.enumerateTextSegments(in: range, type: .standard, options: []) { segmentRange, segment, _, container in
                            if segment.width > 0 {
                                let rect = CGRect(x: segment.minX,
                                    y: baseline - rise - font.ascender,
                                    width: segment.width, height: TextCaret.glyphBoxHeight(of: font))
                                segments.append(Segment(range: segmentRange, rect: rect, baseline: baseline - rise, container: container))
                            }
                            return true
                        }
                    }
                }
            }
            return true
        }
        return segments
    }
}
