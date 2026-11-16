import Foundation
import Models

/// ↵로 넣은 항목이 갈 노트를 고른다(spec 20의 5, 6번 임시 값, D-026).
///
/// "오늘 노트"는 그 스페이스의 노트 가운데 오늘 만든 것이다(노트는 만든 날짜에 속한다).
/// 오늘 만든 것이 여럿이면 가장 먼저 만든 것을 쓴다. 나중에 따로 만든 노트로 옮겨 가지 않는다.
nonisolated enum CaptureDestination {
    static func todayNote(in notes: [Note], spaceID: SpaceID?, now: Date, calendar: Calendar) -> Note? {
        todayNotes(in: notes, spaceID: spaceID, now: now, calendar: calendar).first
    }

    /// 오늘 노트의 후보. 먼저 만든 것이 앞이다. 앞의 노트에 넣을 수 없을 때(충돌, 없어진 파일) 다음 것을 쓴다.
    static func todayNotes(in notes: [Note], spaceID: SpaceID?, now: Date, calendar: Calendar) -> [Note] {
        notes
            .filter { $0.spaceID == spaceID && calendar.isDate($0.created, inSameDayAs: now) }
            .sorted { ($0.created, $0.id.rawValue) < ($1.created, $1.id.rawValue) }
    }

    /// 오늘 노트를 새로 만들 때의 제목. 제목 없는 노트가 날마다 쌓이지 않게 날짜를 적는다.
    static func title(for date: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.month, .day], from: date)
        return "\(parts.month ?? 0)월 \(parts.day ?? 0)일"
    }
}
