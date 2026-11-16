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

    /// 가족 이름 후보. 가변 글꼴은 `Pretendard Variable`처럼 뒤에 Variable이 붙어 등록되므로 그쪽을 먼저 본다.
    /// 시스템에 굵기별 파일로 깔린 같은 이름의 글꼴보다 번들의 가변 글꼴이 먼저 잡힌다.
    static func familyCandidates(_ family: String) -> [String] {
        ["\(family) Variable", family]
    }

    private static func installedFamily(_ family: String) -> String? {
        familyCandidates(family).first {
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
        // 굵기별 파일이 따로 있는 글꼴(D2Coding)은 가족 안에서 굵기가 가장 가까운 파일을 고른다.
        return closestMember(family: family, size: size, weight: weight) ?? base
    }

    /// 가족 안의 기울지 않은 글꼴 가운데 CSS 굵기가 가장 가까운 것.
    private static func closestMember(family: String, size: CGFloat, weight: CGFloat) -> NSFont? {
        let members = (NSFontManager.shared.availableMembers(ofFontFamily: family) ?? [])
            .compactMap { $0.first as? String }
            .compactMap { NSFont(name: $0, size: size) }
            .filter { !$0.fontDescriptor.symbolicTraits.contains(.italic) }
        return members.min { abs(cssWeight($0) - weight) < abs(cssWeight($1) - weight) }
    }

    /// 글꼴의 굵기를 CSS 굵기(100~900)로. 시스템 굵기 눈금(-1~1) 사이는 곧게 잇는다.
    static func cssWeight(_ font: NSFont) -> CGFloat {
        let traits = font.fontDescriptor.object(forKey: .traits) as? [NSFontDescriptor.TraitKey: Any]
        let value = (traits?[.weight] as? NSNumber).map { CGFloat($0.doubleValue) } ?? 0
        let scale: [(NSFont.Weight, CGFloat)] = [
            (.ultraLight, 100), (.thin, 200), (.light, 300), (.regular, 400), (.medium, 500),
            (.semibold, 600), (.bold, 700), (.heavy, 800), (.black, 900),
        ]
        guard value > scale[0].0.rawValue else { return scale[0].1 }
        for (lower, upper) in zip(scale, scale.dropFirst()) where value <= upper.0.rawValue {
            let span = upper.0.rawValue - lower.0.rawValue
            return lower.1 + (upper.1 - lower.1) * (value - lower.0.rawValue) / span
        }
        return scale[scale.count - 1].1
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
