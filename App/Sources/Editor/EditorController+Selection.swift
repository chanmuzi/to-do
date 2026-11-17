import AppKit

extension EditorController {
    func selectionRects() -> [CGRect] {
        let base = contentStorage.documentRange.location
        let origin = textView.textContainerOrigin
        return textView.selectedRanges.flatMap { value -> [CGRect] in
            let selected = value.rangeValue
            guard selected.length > 0,
                  let start = contentStorage.location(base, offsetBy: selected.location),
                  let end = contentStorage.location(start, offsetBy: selected.length),
                  let range = NSTextRange(location: start, end: end) else { return [] }
            return layoutManager.selectionRects(in: range).map { $0.offsetBy(dx: origin.x, dy: origin.y) }
        }
    }
}
