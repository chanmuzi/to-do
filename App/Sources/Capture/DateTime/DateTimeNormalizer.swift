import Foundation

/// 읽기 전에 고른 글: 풀어 쓴 한글(NFD)은 합치고(NFC), 전각 글자와 숫자는 반각으로, 여러 물결표와 줄표는 `~`와 `-`로 바꾼다.
/// 고른 글의 자리를 받은 글의 UTF-16 자리로 되돌릴 수 있다.
nonisolated struct NormalizedText: Sendable {
    let text: String
    /// 고른 글의 UTF-16 단위마다, 그것이 나온 받은 글 글자(문자소)의 시작과 끝.
    private let starts: [Int]
    private let ends: [Int]
    private let originalLength: Int

    init(_ original: String) {
        var text = ""
        var starts: [Int] = []
        var ends: [Int] = []
        var offset = 0
        for character in original {
            let length = character.utf16.count
            let mapped = Self.mapped(character)
            let units = mapped.utf16.count
            starts.append(contentsOf: repeatElement(offset, count: units))
            ends.append(contentsOf: repeatElement(offset + length, count: units))
            text += mapped
            offset += length
        }
        self.text = text
        self.starts = starts
        self.ends = ends
        originalLength = offset
    }

    /// 고른 글의 자리를 받은 글의 자리로.
    func originalRange(_ range: NSRange) -> NSRange {
        guard range.length > 0, range.location < starts.count else {
            let location = range.location < starts.count ? starts[range.location] : originalLength
            return NSRange(location: location, length: 0)
        }
        let start = starts[range.location]
        let end = ends[min(NSMaxRange(range), ends.count) - 1]
        return NSRange(location: start, length: end - start)
    }

    private static func mapped(_ character: Character) -> String {
        let composed = String(character).precomposedStringWithCanonicalMapping
        var result = String.UnicodeScalarView()
        for scalar in composed.unicodeScalars {
            result.append(replacement(for: scalar))
        }
        return String(result)
    }

    private static func replacement(for scalar: Unicode.Scalar) -> Unicode.Scalar {
        switch scalar.value {
        // 전각 ASCII(！부터 ～까지). 전각 물결표는 아래에서 `~`가 된다.
        case 0xFF01...0xFF5E: return Unicode.Scalar(scalar.value - 0xFEE0) ?? scalar
        // 전각 공백, 줄바꿈 없는 공백.
        case 0x3000, 0x00A0: return " "
        // 물결표들.
        case 0x301C, 0x2053: return "~"
        // 줄표들(하이픈, 반각 줄표, 전각 줄표, 빼기표).
        case 0x2010...0x2015, 0x2212: return "-"
        default: return scalar
        }
    }
}
