import Foundation

/// 접힌 토글을 로컬 창 상태에 적고 읽는 표기(D-018, D-023). 노트 파일에는 적지 않는다.
nonisolated enum FoldPersistence {
    /// 접힌 줄 번호와 그 줄의 글을 함께 저장할 모양(오름차순, 같은 개수). 접힌 것이 없으면 `nil`
    /// (상태 파일에 항목을 남기지 않는다).
    /// 줄 번호만 적어 두면 창이 닫힌 사이에 파일이 바뀌었을 때 엉뚱한 토글이 접힌다.
    static func stored(_ folded: Set<Int>, in text: String) -> (lines: [Int], texts: [String])? {
        guard !folded.isEmpty else { return nil }
        let body = lines(of: text)
        let valid = folded.filter { $0 >= 0 && $0 < body.count }.sorted()
        return valid.isEmpty ? nil : (valid, valid.map { String(body[$0]) })
    }

    /// 저장해 둔 접힘을 지금 본문에 맞춰 되살린다(노트를 열 때).
    ///
    /// 줄마다 적어 둔 글이 제자리에 그대로 있으면 그대로 둔다(끝에 줄이 붙은 경우가 그렇다). 제자리는 적어 둔
    /// 줄 번호에 앞의 접힘이 옮겨 간 만큼을 더한 곳이다(위에 줄이 들어오면 아래의 접힘이 모두 같이 밀린다).
    /// 제자리에 없으면 앞의 접힘보다 뒤에서 같은 글의 줄을 찾는데, 그런 줄이 하나뿐일 때만 그리로 옮긴다.
    /// 없거나 여럿이면(같은 글의 토글이 여럿이라 어느 것인지 알 수 없다) 버린다. 엉뚱한 토글을 접느니 펴 둔다.
    /// 줄의 글 없이 적힌 예전 상태(`texts`가 `nil`이거나 개수가 다름)는 견줄 것이 없어 줄 번호를 그대로 쓴다
    /// (음수는 버린다. 손으로 고친 상태 파일).
    /// 되살린 줄이 토글인지는 편집기가 다시 거른다.
    static func restored(lines stored: [Int]?, texts: [String]?, in text: String) -> Set<Int> {
        let indices = stored ?? []
        guard let texts, texts.count == indices.count else { return Set(indices.filter { $0 >= 0 }) }
        let body = lines(of: text)
        var result: Set<Int> = []
        var shift = 0
        var floor = 0
        for (index, expected) in zip(indices, texts).sorted(by: { $0.0 < $1.0 }) {
            let wanted = index + shift
            let found: Int
            if wanted >= floor, wanted < body.count, body[wanted] == expected {
                found = wanted
            } else {
                let candidates = body.indices.filter { $0 >= floor && body[$0] == expected }
                guard candidates.count == 1 else { continue }
                found = candidates[0]
            }
            result.insert(found)
            shift = found - index
            floor = found + 1
        }
        return result
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
