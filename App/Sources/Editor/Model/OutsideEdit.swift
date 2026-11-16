import Foundation

/// 바깥(이 편집기가 아닌 쪽)이 바꾼 원문을 지금 원문과 견주어 얻은, 달라진 가운데 부분.
nonisolated struct OutsideEdit: Equatable, Sendable {
    /// 지금 원문에서 바뀔 범위.
    var range: NSRange
    var replacement: String

    /// 앞뒤의 같은 부분을 뺀 가장 작은 바꿔 쓰기. 같은 글이면 `nil`.
    /// 조합된 글자(대리 쌍)의 한가운데에서 자르지 않는다.
    init?(from old: String, to new: String) {
        let a = Array(old.utf16)
        let b = Array(new.utf16)
        guard a != b else { return nil }
        var prefix = 0
        while prefix < a.count, prefix < b.count, a[prefix] == b[prefix] { prefix += 1 }
        var suffix = 0
        while suffix < a.count - prefix, suffix < b.count - prefix,
              a[a.count - 1 - suffix] == b[b.count - 1 - suffix] { suffix += 1 }
        // 대리 쌍의 뒤쪽 절반에서 시작하거나 앞쪽 절반에서 끝나지 않게 한 칸씩 물린다.
        if prefix > 0, UTF16.isLeadSurrogate(a[prefix - 1]) { prefix -= 1 }
        if suffix > 0, UTF16.isTrailSurrogate(a[a.count - suffix]) { suffix -= 1 }
        range = NSRange(location: prefix, length: a.count - prefix - suffix)
        let middle = Array(b[prefix..<(b.count - suffix)])
        replacement = String(utf16CodeUnits: middle, count: middle.count)
    }

    var delta: Int { replacement.utf16.count - range.length }

    func applied(to text: String) -> String {
        let whole = text as NSString
        guard NSMaxRange(range) <= whole.length else { return text }
        return whole.replacingCharacters(in: range, with: replacement)
    }

    /// 화면에 넣기 전에 원문이 다른 편집(조합 중인 글자)으로 바뀌었다. 가리키는 자리를 따라 옮긴다.
    /// 그 편집이 바뀔 범위에 겹치면 범위에 넣는다.
    mutating func shift(editedRange: NSRange, delta: Int) {
        let oldEnd = NSMaxRange(editedRange) - delta
        if oldEnd <= range.location {
            range.location += delta
        } else if editedRange.location < NSMaxRange(range) {
            range.length = max(0, range.length + delta)
        }
    }

    /// 바꾸기 전의 위치가 바꾼 뒤에 놓일 곳. 바뀐 부분 안에 있던 위치는 바뀐 부분 뒤로 간다.
    /// - Parameter sticksToEnd: 바뀐 부분의 끝에 딱 붙어 있던 위치도 바뀐 부분 뒤로 보낸다(문서 끝의 커서).
    func moved(_ position: Int, sticksToEnd: Bool) -> Int {
        if position < range.location { return position }
        if position > NSMaxRange(range) { return position + delta }
        // 바뀐 부분의 맨 앞에 있던 위치는 그 앞에 남는다(그 자리에 끼워 넣기만 했고 붙어 가야 할 때만 뒤로 간다).
        if position == range.location { return range.length == 0 && sticksToEnd ? position + replacement.utf16.count : position }
        return range.location + replacement.utf16.count
    }
}
