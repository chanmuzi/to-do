import Foundation

public enum LibrarySelection: Hashable, Codable, Sendable {
    case today, floating, all, reminders, archived, trash
    case space(SpaceID?)
    case day(SpaceID?, Date)
    case archive(String)

    public static let views: [Self] = [.today, .floating, .all, .reminders]
}

public struct LibraryPreferences: Codable, Equatable, Sendable {
    public var visibleViews: [LibrarySelection] = [.today, .floating, .all]
    public var openingView: LibrarySelection?
    public var lastSelection: LibrarySelection = .today
    public var pinnedIcons: [SpaceIcon] = []
    public var recentIcons: [SpaceIcon] = []
    public var images: [String] = []
    public init() {}

    /// 항목을 추가하기 전의 파일도 저장된 설정을 보존하면서 읽는다.
    public init(from decoder: any Decoder) throws {
        self.init()
        let container = try decoder.container(keyedBy: CodingKeys.self)
        visibleViews = try container.decodeIfPresent([LibrarySelection].self, forKey: .visibleViews) ?? visibleViews
        openingView = try container.decodeIfPresent(LibrarySelection.self, forKey: .openingView) ?? openingView
        lastSelection = try container.decodeIfPresent(LibrarySelection.self, forKey: .lastSelection) ?? lastSelection
        pinnedIcons = try container.decodeIfPresent([SpaceIcon].self, forKey: .pinnedIcons) ?? pinnedIcons
        recentIcons = try container.decodeIfPresent([SpaceIcon].self, forKey: .recentIcons) ?? recentIcons
        images = try container.decodeIfPresent([String].self, forKey: .images) ?? images
    }
}
