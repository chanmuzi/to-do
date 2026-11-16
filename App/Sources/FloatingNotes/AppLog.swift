import Foundation

/// 표준 오류로 내는 앱 기록. 사용자에게 창으로 알릴 일이 아닌 문제를 남긴다.
enum AppLog {
    static func warning(_ message: String) {
        FileHandle.standardError.write(Data("FloatingNotes: \(message)\n".utf8))
    }
}
