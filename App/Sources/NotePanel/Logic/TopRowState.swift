import Foundation
import Models
import Theme

/// 상단 줄에 무엇을 어떤 색으로 보일지(spec 5.2, 5.5).
/// 입력에 포커스가 없다. 포커스는 창 모습을 바꾸지 않는다(규칙 5).
struct TopRowState: Hashable {
    struct SpaceBadge: Hashable {
        var symbolName: String?
        var emoji: String?
        var name: String?
    }

    struct Pin: Hashable {
        var symbolName: String
        var alpha: Double
        var color: ColorToken
        var isOn: Bool
    }

    static let untitled = "제목 없음"

    /// 스페이스가 없으면 자리 자체가 없다.
    var space: SpaceBadge?
    var spaceColor: ColorToken
    var title: String
    /// 제목이 비어 "제목 없음"을 보통 굵기로 보이는 중.
    var isTitlePlaceholder: Bool
    var titleColor: ColorToken
    /// 호버로 나타나는 것(아이콘 셋, 휴지통, 닫기)의 알파. 자리는 늘 차지한다(규칙 7).
    var hoverControlsAlpha: Double
    var reminder: ReminderPresentation?
    var pin: Pin
    var problem: NoteProblem?

    init(
        note: Note,
        space: Space?,
        isPinned: Bool,
        isHovered: Bool,
        isEditingTitle: Bool,
        problem: NoteProblem?,
        options: NotePanelDisplayOptions,
        now: Date,
        calendar: Calendar
    ) {
        self.space = space.flatMap { Self.badge(for: $0, display: options.space) }
        spaceColor = isHovered ? .text2 : .text3
        title = note.title.isEmpty ? Self.untitled : note.title
        isTitlePlaceholder = note.title.isEmpty
        titleColor = isHovered || isEditingTitle ? .text : .text3
        hoverControlsAlpha = isHovered ? 1 : 0
        reminder = note.reminder.map {
            ReminderPresentation(reminder: $0, now: now, options: options, calendar: calendar)
        }
        pin = isPinned
            ? Pin(symbolName: "pin.fill", alpha: 1, color: isHovered ? .text2 : .text3, isOn: true)
            : Pin(symbolName: "pin", alpha: isHovered ? 1 : 0, color: .text2, isOn: false)
        self.problem = problem
    }

    /// 이미지 아이콘은 Library 단계에서 만든다. 그때까지는 이름으로 대신한다.
    static func badge(for space: Space, display: NotePanelDisplayOptions.SpaceDisplay) -> SpaceBadge? {
        var badge = SpaceBadge()
        if display != .name {
            switch space.icon {
            case .symbol(let name, _): badge.symbolName = name
            case .emoji(let emoji): badge.emoji = emoji
            case .image: break
            }
        }
        let hasIcon = badge.symbolName != nil || badge.emoji != nil
        if display != .icon || !hasIcon { badge.name = space.name }
        if badge.name?.isEmpty == true { badge.name = nil }
        return hasIcon || badge.name != nil ? badge : nil
    }
}
