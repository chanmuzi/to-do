import Foundation

/// 찾을 말. `isComposing`은 검색 칸에서 한글을 조합하는 중인지다.
nonisolated struct BrowseQuery: Hashable, Sendable {
    let text: String
    let isComposing: Bool

    init(_ text: String, isComposing: Bool = false) {
        self.text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        self.isComposing = isComposing
    }

    var isEmpty: Bool { text.isEmpty }
}

/// 글을 견줄 수 있는 꼴로 푼 것: 소문자로 바꾸고 자모 단위(NFD)로 풀어, 글자마다 어느 원래 글자에서 왔는지 적어 둔다.
/// 조합형(NFC)과 풀어 쓴 한글(NFD)이 같은 글로 읽히고, "배"가 "백"의 앞부분으로 읽힌다.
nonisolated struct BrowseSearchText: Sendable {
    let scalars: [UInt32]
    /// `scalars[i]`가 나온 원래 글자(`Character`)의 차례.
    let owners: [Int]

    init(_ text: String) {
        var scalars: [UInt32] = []
        var owners: [Int] = []
        for (index, character) in text.enumerated() {
            for scalar in BrowseMatcher.fold(String(character)) {
                scalars.append(scalar)
                owners.append(index)
            }
        }
        self.scalars = scalars
        self.owners = owners
    }
}

/// 제목과 본문에서 찾기(spec 8): 대소문자를 가리지 않고, 한글은 조합 중인 글자까지 따라간다.
nonisolated enum BrowseMatcher {
    /// 맞은 자리를 원래 글의 글자(`Character`) 차례로 돌려준다.
    static func firstMatch(of query: BrowseQuery, in text: BrowseSearchText) -> Range<Int>? {
        for needle in needles(for: query) {
            if let found = firstRange(of: needle, in: text.scalars) {
                return text.owners[found.lowerBound]..<(text.owners[found.upperBound - 1] + 1)
            }
        }
        return nil
    }

    static func firstMatch(of query: BrowseQuery, in text: String) -> Range<Int>? {
        firstMatch(of: query, in: BrowseSearchText(text))
    }

    /// 찾을 글자 줄. 조합 중이고 마지막 글자에 받침이 있으면, 그 받침이 다음 글자의 첫소리로 넘어간 꼴도 찾는다
    /// (두벌식으로 "배포"를 치는 동안 "뱊"이 되는 때).
    static func needles(for query: BrowseQuery) -> [[UInt32]] {
        let base = fold(query.text)
        guard !base.isEmpty else { return [] }
        guard query.isComposing, let last = base.last, let moved = Hangul.movingFinalToInitial(last) else {
            return [base]
        }
        return [base, Array(base.dropLast()) + moved]
    }

    /// 소문자, 자모 단위. 낱자로 친 호환 자모(ㅂ, ㅏ)는 첫소리와 가운뎃소리 자모로 바꾼다.
    static func fold(_ text: String) -> [UInt32] {
        text.lowercased().decomposedStringWithCanonicalMapping.unicodeScalars.map { Hangul.conjoining($0.value) }
    }

    private static func firstRange(of needle: [UInt32], in haystack: [UInt32]) -> Range<Int>? {
        guard !needle.isEmpty, haystack.count >= needle.count else { return nil }
        for start in 0...(haystack.count - needle.count)
        where haystack[start] == needle[0] && haystack[start..<(start + needle.count)].elementsEqual(needle) {
            return start..<(start + needle.count)
        }
        return nil
    }
}

/// 한글 자모 표.
nonisolated enum Hangul {
    private static let initialBase: UInt32 = 0x1100
    private static let medialBase: UInt32 = 0x1161
    private static let finalBase: UInt32 = 0x11A7

    /// 호환 자모 닿소리(U+3131...)에서 첫소리 차례로. 겹받침 전용 글자는 `nil`.
    private static let compatibilityInitials: [UInt32: UInt32] = [
        0x3131: 0, 0x3132: 1, 0x3134: 2, 0x3137: 3, 0x3138: 4, 0x3139: 5, 0x3141: 6, 0x3142: 7, 0x3143: 8,
        0x3145: 9, 0x3146: 10, 0x3147: 11, 0x3148: 12, 0x3149: 13, 0x314A: 14, 0x314B: 15, 0x314C: 16,
        0x314D: 17, 0x314E: 18,
    ]

    /// 받침 차례(1...27)마다: 남는 받침 차례(없으면 0)와 다음 글자로 넘어가는 첫소리 차례.
    private static let finalSplits: [(stays: UInt32, moves: UInt32)] = [
        (0, 0), (0, 1), (1, 9), (0, 2), (4, 12), (4, 18), (0, 3), (0, 5), (8, 0), (8, 6), (8, 7), (8, 9),
        (8, 16), (8, 17), (8, 18), (0, 6), (0, 7), (17, 9), (0, 9), (0, 10), (0, 11), (0, 12), (0, 14),
        (0, 15), (0, 16), (0, 17), (0, 18),
    ]

    static func conjoining(_ scalar: UInt32) -> UInt32 {
        if let initial = compatibilityInitials[scalar] { return initialBase + initial }
        if (0x314F...0x3163).contains(scalar) { return medialBase + (scalar - 0x314F) }
        return scalar
    }

    /// 받침이면 그 받침을 다음 글자의 첫소리로 넘긴 자모들. 받침이 아니면 `nil`.
    static func movingFinalToInitial(_ scalar: UInt32) -> [UInt32]? {
        guard (finalBase + 1...finalBase + 27).contains(scalar) else { return nil }
        let split = finalSplits[Int(scalar - finalBase) - 1]
        let moved = initialBase + split.moves
        return split.stays == 0 ? [moved] : [finalBase + split.stays, moved]
    }
}
