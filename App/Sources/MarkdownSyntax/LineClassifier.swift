import Foundation

/// 들여쓰기 뒤의 글자를 보고 줄의 종류와 기호 길이를 정한다.
nonisolated package enum LineClassifier {
    private static let space: unichar = 0x20
    private static let tab: unichar = 0x09
    private static let hash: unichar = 0x23
    private static let dash: unichar = 0x2D
    private static let star: unichar = 0x2A
    private static let greater: unichar = 0x3E
    private static let plus: unichar = 0x2B
    private static let backtick: unichar = 0x60

    /// 줄 앞 들여쓰기. 탭 하나 또는 공백 둘이 한 단계다.
    package static func indent(_ u: [unichar], from start: Int, to end: Int) -> (length: Int, level: Int) {
        var i = start
        var tabs = 0
        var spaces = 0
        while i < end {
            if u[i] == tab { tabs += 1 } else if u[i] == space { spaces += 1 } else { break }
            i += 1
        }
        return (i - start, tabs + spaces / 2)
    }

    package static func isFence(_ u: [unichar], from start: Int, to end: Int) -> Bool {
        start + 3 <= end && u[start] == backtick && u[start + 1] == backtick && u[start + 2] == backtick
    }

    /// 닫는 줄은 ``` 뒤에 공백만 있어야 한다.
    package static func isClosingFence(_ u: [unichar], from start: Int, to end: Int) -> Bool {
        guard isFence(u, from: start, to: end) else { return false }
        return !(start + 3..<end).contains { u[$0] != space && u[$0] != tab }
    }

    package static func classify(_ u: [unichar], from start: Int, to end: Int) -> (kind: LineKind, markerLength: Int) {
        guard start < end else { return (.paragraph, 0) }
        let c = u[start]
        if let level = headingLevel(u, from: start, to: end) { return (.heading(level), level + 1) }
        if c == dash || c == star, start + 1 < end, u[start + 1] == space {
            if let todo = todo(u, from: start + 2, to: end) { return (.todo(done: todo.done), 2 + todo.length) }
            return (.bullet, 2)
        }
        // 토글은 `+ `(표준 Markdown의 목록 기호라 다른 앱에서는 하위 항목을 가진 목록으로 읽힌다),
        // `> `는 표준대로 인용문이다(D-044).
        if c == plus, start + 1 < end, u[start + 1] == space {
            if let level = headingLevel(u, from: start + 2, to: end) { return (.toggleHeading(level), level + 3) }
            return (.toggle, 2)
        }
        if c == greater, start + 1 < end, u[start + 1] == space { return (.quote, 2) }
        if let todo = todo(u, from: start, to: end) { return (.todo(done: todo.done), todo.length) }
        return (.paragraph, 0)
    }

    private static func headingLevel(_ units: [unichar], from start: Int, to end: Int) -> Int? {
        var i = start
        while i < end, units[i] == hash { i += 1 }
        let level = i - start
        return (1...3).contains(level) && i < end && units[i] == space ? level : nil
    }

    /// `[ ] `, `[x] `. 줄 끝에서는 공백이 없어도 받는다.
    /// 빈 대괄호 `[] `는 투두로 읽지 않는다. `[]` 뒤에 Space를 칠 때만 `[ ] `로 바꿔 넣는다
    /// (`] 글자` 앞에 `[`를 쳤다고 투두가 되어 커서가 기호 뒤로 밀리지 않게).
    private static func todo(_ u: [unichar], from i: Int, to end: Int) -> (done: Bool, length: Int)? {
        guard i + 2 < end, u[i] == 0x5B, u[i + 2] == 0x5D else { return nil }
        let done: Bool
        switch u[i + 1] {
        case space: done = false
        case 0x78, 0x58: done = true
        default: return nil
        }
        if i + 3 == end { return (done, 3) }
        return u[i + 3] == space ? (done, 4) : nil
    }
}
