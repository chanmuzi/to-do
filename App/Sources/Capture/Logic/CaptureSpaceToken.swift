import Foundation
import Models

/// 글 안에 적은 스페이스 표시 `#이름`(임시, D-026). 이름이 있는 스페이스와 똑같을 때만 읽는다(대소문자 무시).
/// 앞뒤가 글의 끝이거나 공백이어야 한다. 여러 개면 맨 앞의 것.
nonisolated struct CaptureSpaceToken: Hashable, Sendable {
    let spaceID: SpaceID
    /// `#`부터 이름 끝까지(UTF-16).
    let range: NSRange

    static func firstMatch(in text: String, spaces: [Space]) -> CaptureSpaceToken? {
        let source = text as NSString
        // 긴 이름부터 본다(`#회사 일`이 `#회사`보다 먼저).
        let named = spaces.filter { !$0.name.isEmpty }.sorted { $0.name.count > $1.name.count }
        var best: CaptureSpaceToken?
        for space in named {
            let needle = "#" + space.name
            var search = NSRange(location: 0, length: source.length)
            while search.length > 0 {
                let found = source.range(of: needle, options: [.caseInsensitive], range: search)
                guard found.location != NSNotFound else { break }
                if isBoundary(source, before: found.location), isBoundary(source, after: NSMaxRange(found)) {
                    if best.map({ found.location < $0.range.location }) ?? true {
                        best = CaptureSpaceToken(spaceID: space.id, range: found)
                    }
                    break
                }
                search = NSRange(location: NSMaxRange(found), length: source.length - NSMaxRange(found))
            }
        }
        return best
    }

    private static func isBoundary(_ source: NSString, before location: Int) -> Bool {
        location == 0 || isSpace(source.character(at: location - 1))
    }

    private static func isBoundary(_ source: NSString, after location: Int) -> Bool {
        location == source.length || isSpace(source.character(at: location))
    }

    private static func isSpace(_ unit: unichar) -> Bool {
        Unicode.Scalar(unit).map { CharacterSet.whitespacesAndNewlines.contains($0) } ?? false
    }
}
