import CoreGraphics
import Foundation

/// `tokens.json`의 CSS식 문자열을 값으로 바꾼다. 해석하지 못하면 `nil`.
enum TokenValueParser {
    /// `13px`, `1.5px`, `-12px`, `0`. 음수도 받는다(그림자 위치, 번짐 줄임).
    static func points(_ raw: String) -> CGFloat? {
        let text = raw.trimmingCharacters(in: .whitespaces)
        let digits = text.hasSuffix("px") ? String(text.dropLast(2)) : text
        return number(digits).map { CGFloat($0) }
    }

    /// 0 이상인 길이(간격, 모서리, 여백, 흐림).
    static func length(_ raw: String) -> CGFloat? {
        points(raw).flatMap { $0 >= 0 ? $0 : nil }
    }

    /// 0보다 큰 길이(글자 크기, 줄 높이).
    static func size(_ raw: String) -> CGFloat? {
        points(raw).flatMap { $0 > 0 ? $0 : nil }
    }

    /// `.92`, `600`, `-.02`. 십진 표기만 받는다(`nan`, `inf`, `0x10`, `1e3`은 값이 아니다).
    static func number(_ raw: String) -> Double? {
        let text = raw.trimmingCharacters(in: .whitespaces)
        let isNegative = text.hasPrefix("-")
        let parts = (isNegative ? text.dropFirst() : text[...])
            .split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count <= 2,
              parts.contains(where: { !$0.isEmpty }),
              parts.allSatisfy({ $0.allSatisfy { ("0"..."9").contains($0) } })
        else { return nil }
        let whole = parts[0].isEmpty ? "0" : parts[0]
        let fraction = parts.count == 2 && !parts[1].isEmpty ? parts[1] : "0"
        guard let value = Double("\(whole).\(fraction)"), value.isFinite else { return nil }
        return isNegative ? -value : value
    }

    /// 0~1 사이의 수(불투명도).
    static func unitNumber(_ raw: String) -> Double? {
        number(raw).flatMap { (0...1).contains($0) ? $0 : nil }
    }

    /// CSS 글꼴 굵기(1~1000).
    static func weight(_ raw: String) -> Double? {
        number(raw).flatMap { (1...1000).contains($0) ? $0 : nil }
    }

    /// `4` → 4. 단위 없는 1 이상의 정수만 받는다(줄 수 같은 개수).
    static func count(_ raw: String) -> Int? {
        let text = raw.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty, text.count <= 4, text.allSatisfy({ ("0"..."9").contains($0) }),
              let value = Int(text), value >= 1
        else { return nil }
        return value
    }

    /// `26%` → 0.26. 0~100%만 받는다.
    static func fraction(_ raw: String) -> Double? {
        let text = raw.trimmingCharacters(in: .whitespaces)
        guard text.hasSuffix("%"), let percent = number(String(text.dropLast())),
              (0...100).contains(percent)
        else { return nil }
        return percent / 100
    }

    /// `180ms` → 0.18초. 음수는 받지 않는다.
    static func seconds(_ raw: String) -> TimeInterval? {
        let text = raw.trimmingCharacters(in: .whitespaces)
        let value: Double? = if text.hasSuffix("ms") {
            number(String(text.dropLast(2))).map { $0 / 1000 }
        } else if text.hasSuffix("s") {
            number(String(text.dropLast()))
        } else {
            nil
        }
        return value.flatMap { $0 >= 0 ? $0 : nil }
    }

    /// `14deg`, `-12deg` → 도. 한 바퀴(±360도) 안만 받는다.
    static func degrees(_ raw: String) -> Double? {
        let text = raw.trimmingCharacters(in: .whitespaces)
        guard text.hasSuffix("deg"), let value = number(String(text.dropLast(3))),
              (-360...360).contains(value)
        else { return nil }
        return value
    }

    /// `-.02em` → 글자 크기에 곱할 배수.
    static func em(_ raw: String) -> Double? {
        let text = raw.trimmingCharacters(in: .whitespaces)
        guard text.hasSuffix("em") else { return nil }
        return number(String(text.dropLast(2)))
    }

    /// `#RRGGBB`, `#RRGGBBAA`, `rgb(r,g,b)`, `rgba(r,g,b,a)`.
    static func color(_ raw: String) -> RGBA? {
        let text = raw.trimmingCharacters(in: .whitespaces)
        if text.hasPrefix("#") { return hexColor(String(text.dropFirst())) }
        guard let arguments = functionArguments(text, names: ["rgba", "rgb"]) else { return nil }
        let parts = arguments.compactMap(number)
        guard parts.count == arguments.count, parts.count == 3 || parts.count == 4,
              parts.prefix(3).allSatisfy({ (0...255).contains($0) }),
              parts.count == 3 || (0...1).contains(parts[3])
        else { return nil }
        return RGBA(
            red: parts[0] / 255, green: parts[1] / 255, blue: parts[2] / 255,
            alpha: parts.count == 4 ? parts[3] : 1
        )
    }

    /// `cubic-bezier(.25,.1,.25,1)`.
    static func bezier(_ raw: String) -> BezierCurve? {
        guard let arguments = functionArguments(raw, names: ["cubic-bezier"]) else { return nil }
        let parts = arguments.compactMap(number)
        // 시간 축(x)은 0~1 안이어야 곡선이 된다.
        guard parts.count == 4, arguments.count == 4,
              (0...1).contains(parts[0]), (0...1).contains(parts[2])
        else { return nil }
        return BezierCurve(x1: parts[0], y1: parts[1], x2: parts[2], y2: parts[3])
    }

    /// `0 18px 44px -12px rgba(0,0,0,.28),0 4px 12px -2px rgba(0,0,0,.10)`.
    static func shadow(_ raw: String) -> [ShadowLayer]? {
        let layers = splitTopLevel(raw, separator: ",").map { layer -> ShadowLayer? in
            let fields = splitTopLevel(layer, separator: " ")
            guard fields.count == 5,
                  let x = points(fields[0]), let y = points(fields[1]),
                  let blur = length(fields[2]), let spread = points(fields[3]),
                  let color = color(fields[4])
            else { return nil }
            return ShadowLayer(x: x, y: y, blur: blur, spread: spread, color: color)
        }
        let resolved = layers.compactMap { $0 }
        return resolved.count == layers.count && !resolved.isEmpty ? resolved : nil
    }

    /// CSS 여백 줄임 표기(값 1~4개). `10px 14px 18px` → 위 10, 좌우 14, 아래 18.
    static func insets(_ raw: String) -> ThemeInsets? {
        let fields = splitTopLevel(raw, separator: " ")
        let values = fields.compactMap(length)
        guard values.count == fields.count else { return nil }
        switch values.count {
        case 1: return ThemeInsets(top: values[0], trailing: values[0], bottom: values[0], leading: values[0])
        case 2: return ThemeInsets(top: values[0], trailing: values[1], bottom: values[0], leading: values[1])
        case 3: return ThemeInsets(top: values[0], trailing: values[1], bottom: values[2], leading: values[1])
        case 4: return ThemeInsets(top: values[0], trailing: values[1], bottom: values[2], leading: values[3])
        default: return nil
        }
    }

    /// `"Pretendard",-apple-system,sans-serif` → 이름 목록.
    static func fontFamilies(_ raw: String) -> [String]? {
        let names = raw.split(separator: ",").map {
            $0.trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
        }.filter { !$0.isEmpty }
        return names.isEmpty ? nil : names
    }

    // MARK: - 내부

    private static func hexColor(_ hex: String) -> RGBA? {
        guard hex.count == 6 || hex.count == 8, let value = UInt64(hex, radix: 16) else { return nil }
        let rgb = hex.count == 8 ? value >> 8 : value
        let alpha = hex.count == 8 ? Double(value & 0xFF) / 255 : 1
        return RGBA(
            red: Double((rgb >> 16) & 0xFF) / 255,
            green: Double((rgb >> 8) & 0xFF) / 255,
            blue: Double(rgb & 0xFF) / 255,
            alpha: alpha
        )
    }

    private static func functionArguments(_ raw: String, names: [String]) -> [String]? {
        let text = raw.trimmingCharacters(in: .whitespaces)
        guard text.hasSuffix(")"),
              let name = names.first(where: { text.hasPrefix($0 + "(") })
        else { return nil }
        let inner = text.dropFirst(name.count + 1).dropLast()
        return inner.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
    }

    /// 괄호 바깥의 구분자로만 나눈다.
    private static func splitTopLevel(_ raw: String, separator: Character) -> [String] {
        var parts: [String] = []
        var current = ""
        var depth = 0
        for character in raw {
            if character == "(" { depth += 1 }
            if character == ")" { depth -= 1 }
            if character == separator, depth == 0 {
                parts.append(current)
                current = ""
            } else {
                current.append(character)
            }
        }
        parts.append(current)
        return parts.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }
}
