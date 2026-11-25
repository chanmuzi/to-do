import Foundation
import Models
import Theme

/// 상단 줄에 무엇을 어떤 색으로 보일지(spec 5.2, 5.5).
/// 입력에 포커스가 없다. 포커스는 창 모습을 바꾸지 않는다(규칙 5).
struct TopRowState: Hashable {
    struct Pin: Hashable {
        var symbolName: String
        var alpha: Double
        var color: ColorToken
        var isOn: Bool
    }

    static let untitled = "제목 없음"

    var paletteID: String?
    var title: String
    /// 제목이 비어 "제목 없음"을 표시하는 중.
    var isTitlePlaceholder: Bool
    var titleColor: ColorToken
    /// 호버로 나타나는 조작의 알파. 고정 핀은 평소에도 보인다.
    var hoverControlsAlpha: Double
    var clockLabel: String?
    var clockColor: ColorToken
    var hasSchedules: Bool { clockLabel != nil }
    var pin: Pin
    var problem: NoteProblem?
    var problemLabel: String?

    init(
        note: Note,
        isPinned: Bool,
        isHovered: Bool,
        isEditingTitle: Bool,
        problem: NoteProblem?,
        options: NotePanelDisplayOptions,
        now: Date,
        calendar: Calendar
    ) {
        paletteID = note.colorID?.rawValue
        title = note.title.isEmpty ? Self.untitled : note.title
        isTitlePlaceholder = note.title.isEmpty
        titleColor = isHovered || isEditingTitle ? .text : .text3
        hoverControlsAlpha = isHovered ? 1 : 0
        var reminderOptions = options
        reminderOptions.reminder = .time
        let active = note.schedules.filter { !$0.isCompleted && !$0.isDeleted }
        let upcoming = active.filter { $0.isUpcoming(at: now, calendar: calendar) }
        let syncFailed = note.schedules.contains { $0.syncError != nil }
        if let first = upcoming.min(by: { $0.start < $1.start }) {
            var presentation = ReminderPresentation(item: first, now: now, options: reminderOptions, calendar: calendar)
            presentation.syncFailed = syncFailed
            clockLabel = presentation.accessibilityLabel + (upcoming.count > 1 ? " +\(upcoming.count - 1)" : "")
            clockColor = presentation.status == .imminent ? .warn : .text3
        } else {
            clockLabel = active.isEmpty ? nil : "이 노트의 일정 \(active.count)건" + (syncFailed ? " 연동 실패, 앱에 저장됨" : "")
            clockColor = .text3
        }
        pin = isPinned
            ? Pin(symbolName: "pin.fill", alpha: 1, color: isHovered ? .text2 : .text3, isOn: true)
            : Pin(symbolName: "pin", alpha: isHovered ? 1 : 0, color: .text2, isOn: false)
        self.problem = problem
        problemLabel = problem?.accessibilityLabel ?? (active.isEmpty && syncFailed ? "예정 연동 실패" : nil)
    }
}
