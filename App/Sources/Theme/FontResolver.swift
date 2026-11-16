import AppKit
import CoreText

/// 글꼴 이름 후보와 CSS 굵기로 `NSFont`를 만든다.
enum FontResolver {
    /// OpenType 가변 축 `wght`의 식별자.
    private static let weightAxis = 0x7767_6874

    static func font(families: [String], size: CGFloat, weight: CGFloat) -> NSFont {
        for family in families {
            if let generic = genericFont(family, size: size, weight: weight) { return generic }
            if let installed = installedFamily(family),
               let font = font(family: installed, size: size, weight: weight) {
                return font
            }
        }
        return .systemFont(ofSize: size, weight: systemWeight(weight))
    }

    /// 등록된 글꼴 가족 이름. 가변 글꼴은 `Pretendard Variable`처럼 뒤에 Variable이 붙어 등록된다.
    private static func installedFamily(_ family: String) -> String? {
        [family, "\(family) Variable"].first {
            NSFontManager.shared.availableMembers(ofFontFamily: $0) != nil
        }
    }

    private static func font(family: String, size: CGFloat, weight: CGFloat) -> NSFont? {
        let descriptor = NSFontDescriptor(fontAttributes: [.family: family])
        guard let base = NSFont(descriptor: descriptor, size: size) else { return nil }
        if hasWeightAxis(base) {
            let varied = descriptor.addingAttributes([.variation: [weightAxis: weight]])
            return NSFont(descriptor: varied, size: size) ?? base
        }
        // 굵기별 파일이 따로 있는 글꼴(D2Coding)은 굵은 쪽과 보통 쪽 둘 중에서 고른다.
        return weight >= 600 ? NSFontManager.shared.convert(base, toHaveTrait: .boldFontMask) : base
    }

    private static func hasWeightAxis(_ font: NSFont) -> Bool {
        guard let axes = CTFontCopyVariationAxes(font) as? [[CFString: Any]] else { return false }
        return axes.contains { ($0[kCTFontVariationAxisIdentifierKey] as? Int) == weightAxis }
    }

    private static func genericFont(_ name: String, size: CGFloat, weight: CGFloat) -> NSFont? {
        switch name {
        case "-apple-system", "system-ui", "sans-serif":
            .systemFont(ofSize: size, weight: systemWeight(weight))
        case "ui-monospace", "monospace":
            .monospacedSystemFont(ofSize: size, weight: systemWeight(weight))
        default:
            nil
        }
    }

    private static func systemWeight(_ weight: CGFloat) -> NSFont.Weight {
        switch weight {
        case ..<450: .regular
        case ..<550: .medium
        case ..<675: .semibold
        default: .bold
        }
    }
}
