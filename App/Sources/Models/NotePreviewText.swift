/// 화면에 표시할 본문 줄을 한 줄의 미리보기로 잇는다.
package enum NotePreviewText {
    package static func join(_ lines: some Sequence<String>) -> String {
        var result = ""
        for line in lines where !line.isEmpty {
            if let previous = result.last {
                result += previous.isPunctuation ? " " : ", "
            }
            result += line
        }
        return result
    }
}
