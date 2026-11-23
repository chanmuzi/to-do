import Foundation

public enum LibrarySelection: Hashable, Codable, Sendable {
    case today, floating, all, reminders, archived, trash, conversations
    case space(SpaceID?)
    case day(SpaceID?, Date)
    case archive(String)

    public var sidebarViewTitle: String? {
        switch self {
        case .today: "오늘"
        case .floating: "고정됨"
        case .all: "전체 노트"
        case .reminders: "리마인더 있는 노트"
        default: nil
        }
    }

    public static let views: [Self] = [.today, .floating, .all, .reminders]
}

public struct LibraryPreferences: Codable, Equatable, Sendable {
    public private(set) var viewOrder = LibrarySelection.views
    public private(set) var visibleViews: [LibrarySelection] = [.today, .floating, .all]
    public var opensLastSelection = true

    public mutating func resetSidebar() {
        let defaults = LibraryPreferences()
        viewOrder = defaults.viewOrder
        visibleViews = defaults.visibleViews
        opensLastSelection = defaults.opensLastSelection
    }

    public mutating func setVisible(_ view: LibrarySelection, _ visible: Bool) {
        let enabled = Set(visibleViews.filter { $0 != view } + (visible ? [view] : []))
        visibleViews = viewOrder.filter(enabled.contains)
    }

    /// 사이드바에서 숨긴 보기의 자리는 유지한다.
    public mutating func moveView(_ view: LibrarySelection, to target: LibrarySelection, visibleOnly: Bool) {
        let section = visibleOnly ? visibleViews : viewOrder
        guard let from = section.firstIndex(of: view), let to = section.firstIndex(of: target), from != to else { return }
        var reordered = section
        reordered.insert(reordered.remove(at: from), at: to)
        let slots = viewOrder.indices.filter { section.contains(viewOrder[$0]) }
        for (slot, replacement) in zip(slots, reordered) { viewOrder[slot] = replacement }
        visibleViews = viewOrder.filter(Set(visibleViews).contains)
    }

    public var lastSelection: LibrarySelection = .today
    public var pinnedIcons: [SpaceIcon] = []
    public var recentIcons: [SpaceIcon] = []
    public var images: [String] = []
    public init() {}

    /// 항목을 추가하기 전의 파일도 저장된 설정을 보존하면서 읽는다.
    public init(from decoder: any Decoder) throws {
        self.init()
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let order = try container.decodeIfPresent([LibrarySelection].self, forKey: .viewOrder) ?? []
        var seen = Set<LibrarySelection>()
        viewOrder = (order + LibrarySelection.views).filter { LibrarySelection.views.contains($0) && seen.insert($0).inserted }
        let enabled = try container.decodeIfPresent([LibrarySelection].self, forKey: .visibleViews) ?? visibleViews
        visibleViews = viewOrder.filter(Set(enabled).contains)
        enum LegacyKey: CodingKey { case openingView }
        if let opensLast = try container.decodeIfPresent(Bool.self, forKey: .opensLastSelection) {
            opensLastSelection = opensLast
        } else {
            let legacy = try decoder.container(keyedBy: LegacyKey.self)
            opensLastSelection = try legacy.decodeIfPresent(LibrarySelection.self, forKey: .openingView) == nil
        }
        lastSelection = try container.decodeIfPresent(LibrarySelection.self, forKey: .lastSelection) ?? lastSelection
        pinnedIcons = try container.decodeIfPresent([SpaceIcon].self, forKey: .pinnedIcons) ?? pinnedIcons
        recentIcons = try container.decodeIfPresent([SpaceIcon].self, forKey: .recentIcons) ?? recentIcons
        images = try container.decodeIfPresent([String].self, forKey: .images) ?? images
    }
}
