import Foundation

/// 리마인더는 노트당 하나다(spec 20의 8번 임시 값). 캡처로 넣은 항목의 리마인더는 그 노트에 걸리고,
/// 아직 오지 않은 리마인더가 이미 있으면 더 이른 쪽이 남는다.
///
/// 이미 지난 리마인더(지금과 같거나 앞)는 없는 것으로 친다: 지난 값이 새 리마인더를 막지 않는다.
/// 이 규칙에서는 노트에 직접 건 더 늦은 리마인더가 캡처의 더 이른 리마인더로 바뀔 수 있다(임시, 이슈 #4에서 다시 본다).
nonisolated enum ReminderRule {
    static func merged(existing: Date?, new: Date?, now: Date) -> Date? {
        let upcoming = existing.flatMap { $0 > now ? $0 : nil }
        switch (upcoming, new) {
        case let (upcoming?, new?): return min(upcoming, new)
        case let (upcoming?, nil): return upcoming
        case let (nil, new?): return new
        // 새로 걸 것이 없으면 있던 값(지난 것이어도)을 건드리지 않는다.
        case (nil, nil): return existing
        }
    }
}
