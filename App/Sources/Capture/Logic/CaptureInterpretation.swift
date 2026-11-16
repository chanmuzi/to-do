import Foundation
import Models

/// 캡처 바에 적은 글 한 줄을 읽은 결과(spec 7).
nonisolated struct CaptureInterpretation: Hashable, Sendable {
    /// 노트에 넣을 글. `#스페이스` 표시는 빼고, 날짜와 시간 표현(범위 포함)은 적은 그대로 둔다(D-026).
    let text: String
    let spaceID: SpaceID?
    let reminder: Date?
    /// 글에서 알아들은 날짜와 시간 표현. ⌘R로 직접 골랐으면 없다.
    let expression: DateTimeExpression?

    /// 밑줄을 그을 자리. 입력 칸의 글(고치기 전) 기준이다.
    var timeRange: NSRange? { expression?.range }

    var isEmpty: Bool { text.isEmpty }

    /// - Parameters:
    ///   - selectedSpace: ⇥로 고른 스페이스. 글 안의 `#이름`이 있으면 그쪽이 우선한다.
    ///   - manualReminder: ⌘R로 고른 리마인더. 있으면 글에서 읽은 시간보다 우선하고 밑줄도 긋지 않는다.
    init(
        raw: String,
        spaces: [Space],
        selectedSpace: SpaceID?,
        manualReminder: Date?,
        now: Date,
        calendar: Calendar
    ) {
        let token = CaptureSpaceToken.firstMatch(in: raw, spaces: spaces)
        let found = manualReminder == nil
            ? DateTimeParser.firstExpression(in: raw, now: now, calendar: calendar) : nil
        spaceID = token?.spaceID ?? selectedSpace
        // 범위로 적었으면 리마인더는 시작에 건다. 끝은 `expression`에 남고, 적은 글도 그대로 둔다.
        reminder = manualReminder ?? found?.start
        expression = found
        text = Self.clean(raw, removing: token?.range)
    }

    /// 줄바꿈은 공백으로, 표시를 뺀 자리의 겹친 공백은 하나로, 앞뒤 공백은 없앤다.
    private static func clean(_ raw: String, removing range: NSRange?) -> String {
        var source = raw as NSString
        if let range { source = source.replacingCharacters(in: range, with: " ") as NSString }
        return (source as String)
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}
