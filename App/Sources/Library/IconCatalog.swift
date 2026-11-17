import AppKit
import CoreText
import Foundation
import Models

/// 시스템이 설치한 목록을 읽는다. 비공개 API를 호출하지 않으며 경로가 없으면 실패를 화면에 알린다.
/// SF Symbols는 설치된 기호 이름을, 이모지는 시스템 한글/영문 이름과 피부색 변형을 쓴다.
struct IconCatalog {
    static let shared = IconCatalog()
    struct Entry: Identifiable {
        let icon: SpaceIcon
        let name: String
        var id: SpaceIcon { icon }
    }
    let symbols: [Entry]
    let emoji: [Entry]
    let warning: String?

    init() {
        func plist(_ path: String) throws -> Any {
            try PropertyListSerialization.propertyList(from: Data(contentsOf: URL(fileURLWithPath: path)), format: nil)
        }
        var problems: [String] = []
        do {
            let names = try plist("/System/Library/CoreServices/CoreGlyphs.bundle/Contents/Resources/symbol_order.plist") as? [String] ?? []
            symbols = names.map { Entry(icon: .symbol(name: $0, colorID: nil), name: $0) }
            if names.isEmpty { problems.append("시스템 기호 목록을 찾지 못했습니다.") }
        } catch { symbols = []; problems.append("시스템 기호 목록을 읽지 못했습니다: \(error.localizedDescription)") }
        do {
            let base = "/System/Library/PrivateFrameworks/CoreEmoji.framework/Versions/A/Resources/"
            let korean = try plist(base + "ko.lproj/AppleName.strings") as? [String: String] ?? [:]
            let english = try plist(base + "en.lproj/AppleName.strings") as? [String: String] ?? [:]
            let keys = Set(korean.keys).union(english.keys)
            emoji = keys.sorted().flatMap { value -> [Entry] in
                let name = "\(korean[value] ?? "") \(english[value] ?? "") \(value)"
                let base = Entry(icon: .emoji(value), name: name)
                guard value.unicodeScalars.contains(where: { $0.properties.isEmojiModifierBase }),
                      !value.unicodeScalars.contains(where: { $0.properties.isEmojiModifier }) else { return [base] }
                let variants = (0x1F3FB...0x1F3FF).compactMap { code -> Entry? in
                    guard let modifier = Unicode.Scalar(code) else { return nil }
                    var scalars = String.UnicodeScalarView()
                    var followsModifier = false
                    for scalar in value.unicodeScalars {
                        if scalar.value == 0xFE0F && followsModifier { followsModifier = false; continue }
                        scalars.append(scalar)
                        followsModifier = scalar.properties.isEmojiModifierBase
                        if followsModifier { scalars.append(modifier) }
                    }
                    let variant = String(scalars)
                    guard Self.supportsEmoji(variant) else { return nil }
                    return Entry(icon: .emoji(variant), name: name + " " + variant)
                }
                return [base] + variants
            }
            if keys.isEmpty { problems.append("시스템 이모지 목록을 찾지 못했습니다.") }
        } catch { emoji = []; problems.append("시스템 이모지 목록을 읽지 못했습니다: \(error.localizedDescription)") }
        warning = problems.isEmpty ? nil : problems.joined(separator: "\n")
    }
    static func supportsEmoji(_ value: String) -> Bool {
        guard value.count == 1, value.unicodeScalars.contains(where: { $0.properties.isEmoji }) else { return false }
        let font = NSFont(name: "Apple Color Emoji", size: NSFont.systemFontSize) ?? NSFont.systemFont(ofSize: NSFont.systemFontSize)
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: value, attributes: [.font: font]))
        return CTLineGetGlyphCount(line) == 1
    }

}
