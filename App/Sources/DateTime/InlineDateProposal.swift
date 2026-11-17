import Foundation
import Models

/// 같은 읽기 규칙에 커서 조건만 더한다. 범위는 호출자가 준 한 줄의 UTF-16 좌표다.
public struct InlineDateProposal: Equatable, Sendable {
    public let expression: DateTimeExpression
    public let item: ScheduleItem
    public static func == (lhs: Self, rhs: Self) -> Bool { lhs.expression == rhs.expression }

    public static func find(in text: String, caret: Int, now: Date, calendar: Calendar,
                            excluding: [NSRange] = []) -> Self? {
        let source = text as NSString
        guard caret > 0, caret <= source.length else { return nil }
        var units = Array(text.utf16)
        // 지운 뒤 다시 파싱하면 떨어진 두 표현이 붙을 수 있다. 길이를 유지한 차단 문자로 가린다.
        for range in excluding {
            let safe = NSIntersectionRange(range, NSRange(location: 0, length: units.count))
            for index in safe.location..<NSMaxRange(safe) { units[index] = 0xFFFF }
        }
        let masked = String(utf16CodeUnits: units, count: units.count)
        guard let expression = DateTimeParser.firstExpression(in: masked, now: now, calendar: calendar),
              expression.ranges.last.map(NSMaxRange) == caret,
              !expression.ranges.contains(where: { range in excluding.contains { NSIntersectionRange(range, $0).length > 0 } })
        else { return nil }
        let start = expression.isDateOnly ? calendar.startOfDay(for: expression.start) : expression.start
        guard expression.isDateOnly ? start >= calendar.startOfDay(for: now)
                : start > now && !expression.assumptions.contains(.past) else { return nil }
        let end = expression.end.map {
            expression.isDateOnly ? calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: $0))! : $0
        }
        return Self(expression: expression, item: ScheduleItem(start: start, end: end,
                                                               isDateOnly: expression.isDateOnly, modified: now))
    }

    /// 한 줄 필드용. 본문은 Markdown의 기호 보존 삭제 경로를 쓴다.
    public func removingFromTitle(_ text: String) -> String {
        var result = text as NSString
        for range in expression.ranges.reversed() {
            var lower = range.location
            var upper = NSMaxRange(range)
            while lower > 0, result.character(at: lower - 1) == 32 { lower -= 1 }
            while upper < result.length, result.character(at: upper) == 32 { upper += 1 }
            let space = lower > 0 && upper < result.length ? " " : ""
            result = result.replacingCharacters(in: NSRange(location: lower, length: upper - lower), with: space) as NSString
        }
        return result as String
    }
}

/// Features끼리 참조하지 않고 App이 저장 경로와 되돌리기 효과를 연결한다.
public struct InlineDateAcceptance: Sendable {
    public let item: ScheduleItem
    public let source: InlineScheduleSource
    public let todo: TodoAnchor?
    public let previousText: String
    public let nextText: String
    public init(item: ScheduleItem, source: InlineScheduleSource, todo: TodoAnchor?, previousText: String, nextText: String) {
        self.item = item; self.source = source; self.todo = todo
        self.previousText = previousText; self.nextText = nextText
    }
}

@MainActor public final class InlineDateEffect {
    public let undo: () throws -> Void
    public let redo: () throws -> Void
    public init(undo: @escaping () throws -> Void, redo: @escaping () throws -> Void) {
        self.undo = undo; self.redo = redo
    }
}
