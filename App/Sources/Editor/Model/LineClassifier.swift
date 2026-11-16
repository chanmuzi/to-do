import Foundation

/// 들여쓰기 뒤의 글자를 보고 줄의 종류와 기호 길이를 정한다.
nonisolated enum LineClassifier {
    private static let space: unichar = 0x20
    private static let tab: unichar = 0x09
    private static let hash: unichar = 0x23
    private static let dash: unichar = 0x2D
    private static let star: unichar = 0x2A
    private static let greater: unichar = 0x3E
    private static let backtick: unichar = 0x60

    /// 줄 앞 들여쓰기. 탭 하나 또는 공백 둘이 한 단계다.
    static func indent(_ u: [unichar], from start: Int, to end: Int) -> (length: Int, level: Int) {
        var i = start
        var tabs = 0
        var spaces = 0
        while i < end {
            if u[i] == tab { tabs += 1 } else if u[i] == space { spaces += 1 } else { break }
            i += 1
        }
        return (i - start, tabs + spaces / 2)
    }

    static func isFence(_ u: [unichar], from start: Int, to end: Int) -> Bool {
        start + 3 <= end && u[start] == backtick && u[start + 1] == backtick && u[start + 2] == backtick
    }

    /// 닫는 줄은 ``` 뒤에 공백만 있어야 한다.
    static func isClosingFence(_ u: [unichar], from start: Int, to end: Int) -> Bool {
        guard isFence(u, from: start, to: end) else { return false }
        return !(start + 3..<end).contains { u[$0] != space && u[$0] != tab }
    }

    static func classify(_ u: [unichar], from start: Int, to end: Int) -> (kind: LineKind, markerLength: Int) {
        guard start < end else { return (.paragraph, 0) }
        let c = u[start]
        if c == hash {
            var n = 0
            while start + n < end, u[start + n] == hash { n += 1 }
            if n <= 3, start + n < end, u[start + n] == space { return (.heading(n), n + 1) }
            return (.paragraph, 0)
        }
        if c == dash || c == star, start + 1 < end, u[start + 1] == space {
            if let todo = todo(u, from: start + 2, to: end) { return (.todo(done: todo.done), 2 + todo.length) }
            return (.bullet, 2)
        }
        if c == greater, start + 1 < end, u[start + 1] == space { return (.toggle, 2) }
        if let todo = todo(u, from: start, to: end) { return (.todo(done: todo.done), todo.length) }
        return (.paragraph, 0)
    }

    /// `[] `, `[ ] `, `[x] `. 세 글자 꼴은 줄 끝에서 공백이 없어도 받는다.
    private static func todo(_ u: [unichar], from i: Int, to end: Int) -> (done: Bool, length: Int)? {
        guard i + 1 < end, u[i] == 0x5B else { return nil }
        if u[i + 1] == 0x5D {
            return i + 2 < end && u[i + 2] == space ? (false, 3) : nil
        }
        guard i + 2 < end, u[i + 2] == 0x5D else { return nil }
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
