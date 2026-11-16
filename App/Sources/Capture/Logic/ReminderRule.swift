import Foundation

/// 리마인더는 노트당 하나다(spec 20의 8번 임시 값). 캡처로 넣은 항목의 리마인더는 그 노트에 걸리고,
/// 이미 있으면 더 이른 쪽이 남는다.
nonisolated enum ReminderRule {
    static func merged(existing: Date?, new: Date?) -> Date? {
        switch (existing, new) {
        case let (existing?, new?): min(existing, new)
        case let (existing?, nil): existing
        case let (nil, new): new
        }
    }
}
