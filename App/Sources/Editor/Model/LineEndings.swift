import Foundation

/// 편집기의 원문은 줄바꿈이 언제나 `\n` 하나다. 밖에서 들어오는 글(`text`, 붙여넣기, 끌어다 놓기)의
/// `\r\n`, `\r`, U+2028(줄 구분), U+2029(문단 구분)를 `\n`으로 바꾼다.
nonisolated enum LineEndings {
    private static let lineFeed: unichar = 0x0A
    private static let carriageReturn: unichar = 0x0D
    private static let lineSeparator: unichar = 0x2028
    private static let paragraphSeparator: unichar = 0x2029

    private static func isForeign(_ unit: unichar) -> Bool {
        unit == carriageReturn || unit == lineSeparator || unit == paragraphSeparator
    }

    static func needsNormalizing(_ text: String) -> Bool {
        text.utf16.contains(where: isForeign)
    }

    static func normalized(_ text: String) -> String {
        guard needsNormalizing(text) else { return text }
        let units = Array(text.utf16)
        var out: [unichar] = []
        out.reserveCapacity(units.count)
        var index = 0
        while index < units.count {
            let unit = units[index]
            if isForeign(unit) {
                out.append(lineFeed)
                // `\r\n`은 줄바꿈 하나다.
                if unit == carriageReturn, index + 1 < units.count, units[index + 1] == lineFeed { index += 1 }
            } else {
                out.append(unit)
            }
            index += 1
        }
        return String(utf16CodeUnits: out, count: out.count)
    }
}
