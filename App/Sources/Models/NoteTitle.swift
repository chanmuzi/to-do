import Foundation

/// 제목은 한 줄이다. CRLF도 하나의 줄바꿈으로 보고 공백 하나로 바꾼다.
public enum NoteTitle {
    public static func singleLine(_ text: String) -> String {
        text.replacingOccurrences(of: "\r\n", with: "\n")
            .components(separatedBy: .newlines).joined(separator: " ")
    }
}
