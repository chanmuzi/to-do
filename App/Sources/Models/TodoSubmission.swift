import CryptoKit
import Foundation

/// 실행 전용 접수 파일. 대상은 노트 목록에서 확인한 파일 이름에서 확장자를 뺀 값이다.
package struct TodoSubmission: Codable, Hashable, Sendable {
    package let noteID: String
    package let lines: [String]
    package let version: String

    package init(noteID: String, lines: [String], version: String) {
        self.noteID = noteID
        self.lines = lines
        self.version = version
    }

    package static func fingerprint(_ bytes: Data) -> String {
        SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
    }

    package static func valid(lines: [String]) -> Bool {
        (1...32).contains(lines.count) && lines.allSatisfy {
            !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.utf8.count <= 1024
                && $0.unicodeScalars.allSatisfy { !CharacterSet.controlCharacters.union(.newlines).contains($0) }
        }
    }
}
