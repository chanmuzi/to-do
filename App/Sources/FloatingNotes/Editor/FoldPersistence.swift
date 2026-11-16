import Foundation

/// 접힌 토글을 로컬 창 상태에 적고 읽는 표기(D-018, D-023). 노트 파일에는 적지 않는다.
nonisolated enum FoldPersistence {
    /// 저장할 모양: 오름차순 줄 번호. 접힌 것이 없으면 `nil`(상태 파일에 항목을 남기지 않는다).
    static func stored(_ lines: Set<Int>) -> [Int]? {
        let valid = lines.filter { $0 >= 0 }.sorted()
        return valid.isEmpty ? nil : valid
    }

    /// 저장된 값에서 접힌 줄 번호를 꺼낸다. 음수는 버린다(손으로 고친 상태 파일).
    static func lines(from stored: [Int]?) -> Set<Int> {
        Set((stored ?? []).filter { $0 >= 0 })
    }

    /// 편집기 밖에서 본문이 바뀌었을 때(다른 프로그램이 파일을 고침) 접힌 줄 번호를 새 본문에 맞춰 옮긴다.
    /// 앞뒤에서 그대로인 줄을 찾아, 바뀐 곳보다 위의 접힘은 그대로 두고 아래의 접힘은 늘거나 준 줄 수만큼 옮긴다.
    /// 바뀐 줄에 걸친 접힘은 버린다. 옮긴 줄이 새 본문에서 토글인지는 편집기가 다시 거른다.
    static func remapped(_ folded: Set<Int>, from oldText: String, to newText: String) -> Set<Int> {
        guard !folded.isEmpty else { return [] }
        let old = lines(of: oldText)
        let new = lines(of: newText)
        var prefix = 0
        while prefix < min(old.count, new.count), old[prefix] == new[prefix] { prefix += 1 }
        var suffix = 0
        while suffix < min(old.count, new.count) - prefix,
              old[old.count - 1 - suffix] == new[new.count - 1 - suffix] { suffix += 1 }
        let delta = new.count - old.count
        return Set(folded.compactMap { line in
            if line < prefix { return line }
            if line >= old.count - suffix { return line + delta }
            return nil
        })
    }

    /// 편집기와 같은 기준으로 줄을 나눈다(`\r\n`, `\r`, U+2028, U+2029도 줄바꿈 하나).
    private static func lines(of text: String) -> [Substring] {
        text.replacingOccurrences(of: "\r\n", with: "\n")
            .split(omittingEmptySubsequences: false) { $0 == "\n" || $0 == "\r" || $0 == "\u{2028}" || $0 == "\u{2029}" }
    }
}
