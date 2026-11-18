import Foundation
import Models

public enum CalendarAccess: Sendable {
    case available, needsRequest, blocked
}

public struct CalendarChoice: Identifiable, Hashable, Sendable {
    public let id: String
    public let destination: ScheduleDestination
    public init(id: String, destination: ScheduleDestination) {
        self.id = id
        self.destination = destination
    }
}

@MainActor
public protocol CalendarBridge: AnyObject {
    var onChange: (@MainActor () -> Void)? { get set }
    var preferredID: (ScheduleItem.Kind) -> String? { get set }
    func access(for kind: ScheduleItem.Kind) -> CalendarAccess
    func writableChoices(for kind: ScheduleItem.Kind) -> [CalendarChoice]
    func systemDefault(for kind: ScheduleItem.Kind) -> ScheduleDestination?
    func authorize(_ kind: ScheduleItem.Kind, request: Bool) async throws -> Bool
    /// nil은 권한을 확인한 뒤 두 식별자로도 찾지 못한 경우뿐이다.
    func fetch(_ item: ScheduleItem) throws -> ScheduleItem?
    func save(_ item: ScheduleItem) throws -> ScheduleItem
    func remove(_ item: ScheduleItem) throws
    func destination(for item: ScheduleItem) -> ScheduleDestination?
    func events(in interval: DateInterval) -> [CalendarEvent]
    func stop()
}

public enum CalendarBridgeError: Error, LocalizedError {
    case denied, noDefaultCalendar, readOnly, ambiguous, invalidDate
    public var errorDescription: String? {
        switch self {
        case .denied: "연동 접근이 허용되지 않았습니다"
        case .noDefaultCalendar: "기본 캘린더 또는 미리 알림 목록이 없습니다"
        case .readOnly: "이 캘린더는 수정할 수 없습니다"
        case .ambiguous: "연결된 항목을 하나로 찾을 수 없습니다"
        case .invalidDate: "종료는 시작보다 뒤여야 합니다"
        }
    }
}

/// 실제 계정, 권한 API를 호출하지 않는 확인용 양방향 저장소.
@MainActor
public final class FakeCalendarBridge: CalendarBridge {
    public var onChange: (@MainActor () -> Void)?
    public var items: [String: ScheduleItem] = [:]
    public private(set) var openedURL: URL?
    public func open(_ url: URL) { openedURL = url }
    public var isAllowed = true { didSet { if oldValue != isAllowed { onChange?() } } }
    public var preferredID: (ScheduleItem.Kind) -> String? = { _ in nil }
    public var accessByKind: [ScheduleItem.Kind: CalendarAccess] = [:] { didSet { onChange?() } }
    public var readOnlyIDs: Set<String> = [] { didSet { onChange?() } }
    public var additionalChoices: [ScheduleItem.Kind: [CalendarChoice]] = [
        .event: [.init(id: "work", destination: .init(name: "업무", color: .init(red: 0.40, green: 0.64, blue: 0.48)))],
        .reminder: [.init(id: "shopping", destination: .init(name: "장보기", color: .init(red: 0.60, green: 0.46, blue: 0.68)))]
    ] { didSet { onChange?() } }
    public func access(for kind: ScheduleItem.Kind) -> CalendarAccess {
        accessByKind[kind] ?? (isAllowed ? .available : .blocked)
    }
    public func systemDefault(for kind: ScheduleItem.Kind) -> ScheduleDestination? {
        guard access(for: kind) == .available else { return nil }
        return kind == .event ? eventDestination : reminderDestination
    }
    public func writableChoices(for kind: ScheduleItem.Kind) -> [CalendarChoice] {
        guard access(for: kind) == .available else { return [] }
        let system = systemDefault(for: kind).map { CalendarChoice(id: kind.rawValue, destination: $0) }
        return ([system].compactMap { $0 } + (additionalChoices[kind] ?? [])).filter { !readOnlyIDs.contains($0.id) }
    }
    public var eventDestination: ScheduleDestination? = .init(name: "개인 일정", color: .init(red: 0.25, green: 0.52, blue: 0.80))
    public var reminderDestination: ScheduleDestination? = .init(name: "할 일", color: .init(red: 0.85, green: 0.53, blue: 0.22))
    public var linkedDestinations: [String: ScheduleDestination] = [:]
    public func destination(for item: ScheduleItem) -> ScheduleDestination? {
        guard access(for: item.kind) == .available else { return nil }
        if let link = item.link, link.kind == nil || link.kind == item.kind {
            return linkedDestinations[link.localID] ?? (item.kind == .event ? eventDestination : reminderDestination)
        }
        return writableChoices(for: item.kind).first { $0.id == preferredID(item.kind) }?.destination ?? systemDefault(for: item.kind)
    }
    public var authorizationGate: (@MainActor () async -> Void)?
    public var authorizationFailure: CalendarBridgeError?
    public var failure: CalendarBridgeError?
    public private(set) var authorizationRequests: [ScheduleItem.Kind] = []
    public private(set) var authorizationPromptAttempts: [ScheduleItem.Kind] = []
    public private(set) var saves = 0
    public private(set) var reads = 0
    public private(set) var eventRangeReads = 0

    public init(sampleEventsAt now: Date? = nil) {
        guard let now else { return }
        for (index, title) in ["팀 회의", "책 반납"].enumerated() {
            let id = "sample-event-\(index)"
            let start = now.addingTimeInterval(Double(index + 1) * 3600)
            items[id] = ScheduleItem(id: id, start: start, end: start.addingTimeInterval(1800), title: title,
                                     link: .init(localID: id, externalID: id, kind: .event))
        }
    }

    public func events(in interval: DateInterval) -> [CalendarEvent] {
        guard access(for: .event) == .available else { return [] }
        eventRangeReads += 1
        return items.values.compactMap { item in
            guard let end = item.end, !item.isDeleted, !item.isCompleted,
                  item.start < interval.end, end > interval.start else { return nil }
            return CalendarEvent(item: item, destination: destination(for: item))
        }
    }
    public func authorize(_ kind: ScheduleItem.Kind, request: Bool) async throws -> Bool {
        if request { authorizationPromptAttempts.append(kind) }
        await authorizationGate?()
        if let authorizationFailure { throw authorizationFailure }
        if request && !authorizationRequests.contains(kind) { authorizationRequests.append(kind) }
        if request, access(for: kind) == .needsRequest { accessByKind[kind] = isAllowed ? .available : .blocked }
        return access(for: kind) == .available
    }
    public func fetch(_ item: ScheduleItem) throws -> ScheduleItem? {
        reads += 1
        if let failure { throw failure }
        guard access(for: item.kind) == .available else { throw CalendarBridgeError.denied }
        guard var remote = items[item.link?.externalID ?? item.id] else { return nil }
        // 외부 저장소의 식별자는 그대로여도 소유 노트와 로컬 항목 ID는 복구 때 바뀔 수 있다.
        remote.id = item.id
        remote.todo = item.todo
        remote.inlineSource = item.inlineSource
        return remote
    }
    public func save(_ item: ScheduleItem) throws -> ScheduleItem {
        if let failure { throw failure }
        guard access(for: item.kind) == .available else { throw CalendarBridgeError.denied }
        var saved = item
        let externalID = item.link?.externalID ?? item.id
        saved.link = .init(localID: item.link?.localID ?? "fake-" + item.id, externalID: externalID, kind: item.kind)
        if let id = saved.link?.localID, item.link == nil || item.link?.kind != item.kind {
            linkedDestinations[id] = destination(for: item)
        }
        saved.modified = Date()
        items[externalID] = saved
        saves += 1
        return saved
    }
    public func remove(_ item: ScheduleItem) throws {
        if let failure { throw failure }
        guard access(for: item.kind) == .available else { throw CalendarBridgeError.denied }
        items[item.link?.externalID ?? item.id] = nil
    }
    public func changeExternally(_ id: String, _ mutate: (inout ScheduleItem) -> Void) {
        guard var item = items[id] else { return }
        mutate(&item)
        item.modified = Date()
        items[id] = item
        onChange?()
    }
    public func deleteExternally(_ id: String) { items[id] = nil; onChange?() }
    public func stop() { onChange = nil }
}
