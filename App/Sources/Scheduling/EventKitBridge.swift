import AppKit
import EventKit
import Foundation
import Models

/// 생성자는 EventKit에 닿지 않는다. authorize의 명시 요청/기존 전체 권한 확인 뒤에만 저장소를 만든다.
/// API 근거: Apple TN3153, accessing-the-event-store, updating-with-notifications (spec 21).
@MainActor
public final class EventKitBridge: CalendarBridge {
    public var onChange: (@MainActor () -> Void)?
    private var storage: EKEventStore?
    private var observer: (any NSObjectProtocol)?
    private var requested: Set<ScheduleItem.Kind> = []
    public init() {}
    public var preferredID: (ScheduleItem.Kind) -> String? = { _ in nil }

    public func access(for kind: ScheduleItem.Kind) -> CalendarAccess {
        switch EKEventStore.authorizationStatus(for: kind == .event ? .event : .reminder) {
        case .fullAccess: .available
        case .notDetermined: .needsRequest
        default: .blocked
        }
    }
    public func writableChoices(for kind: ScheduleItem.Kind) -> [CalendarChoice] {
        guard access(for: kind) == .available else { return [] }
        return store().calendars(for: kind == .event ? .event : .reminder)
            .filter(\.allowsContentModifications)
            .map { CalendarChoice(id: $0.calendarIdentifier, destination: destination(for: $0), account: $0.source.title) }
            .sorted { $0.destination.name.localizedStandardCompare($1.destination.name) == .orderedAscending }
    }
    private func defaultCalendar(_ kind: ScheduleItem.Kind, in store: EKEventStore) -> EKCalendar? {
        kind == .event ? store.defaultCalendarForNewEvents : store.defaultCalendarForNewReminders()
    }
    public func systemDefault(for kind: ScheduleItem.Kind) -> ScheduleDestination? {
        guard access(for: kind) == .available else { return nil }
        return defaultCalendar(kind, in: store()).map(destination(for:))
    }
    private func newItemCalendar(_ kind: ScheduleItem.Kind, in store: EKEventStore) -> EKCalendar? {
        if let id = preferredID(kind), let calendar = store.calendar(withIdentifier: id),
           calendar.allowsContentModifications,
           calendar.allowedEntityTypes.contains(kind == .event ? .event : .reminder) { return calendar }
        return defaultCalendar(kind, in: store)
    }

    private func store() -> EKEventStore {
        if let storage { return storage }
        let value = EKEventStore()
        storage = value
        observer = NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: value, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in self?.onChange?() }
        }
        return value
    }
    public func destination(for item: ScheduleItem) -> ScheduleDestination? {
        guard EKEventStore.authorizationStatus(for: item.kind == .event ? .event : .reminder) == .fullAccess else { return nil }
        let store = store()
        let calendar: EKCalendar?
        if let link = item.link, link.kind == nil || link.kind == item.kind {
            guard let existing = try? find(item, in: store) else { return nil }
            calendar = existing.calendar
        } else {
            calendar = newItemCalendar(item.kind, in: store)
        }
        guard let calendar else { return nil }
        return destination(for: calendar)
    }
    private func destination(for calendar: EKCalendar) -> ScheduleDestination {
        let color = calendar.cgColor.flatMap { NSColor(cgColor: $0)?.usingColorSpace(.sRGB) }
        return ScheduleDestination(name: calendar.title, color: color.map { .init(red: $0.redComponent, green: $0.greenComponent, blue: $0.blueComponent) })
    }
    public func events(in interval: DateInterval) -> [CalendarEvent] {
        guard EKEventStore.authorizationStatus(for: .event) == .fullAccess else { return [] }
        let store = store()
        let predicate = store.predicateForEvents(withStart: interval.start, end: interval.end, calendars: nil)
        return store.events(matching: predicate).compactMap { event in
            guard event.status != .canceled, let start = event.startDate,
                  let item = decoded(event, retaining: ScheduleItem(id: event.calendarItemIdentifier, start: start)) else { return nil }
            return CalendarEvent(item: item, destination: destination(for: event.calendar), recurring: event.hasRecurrenceRules || event.isDetached)
        }
    }
    public func authorize(_ kind: ScheduleItem.Kind, request: Bool) async throws -> Bool {
        let type: EKEntityType = kind == .event ? .event : .reminder
        let status = EKEventStore.authorizationStatus(for: type)
        if status == .fullAccess { _ = store(); return true }
        guard status == .notDetermined, request, requested.insert(kind).inserted else { return false }
        let granted: Bool
        do {
            if kind == .event { granted = try await store().requestFullAccessToEvents() }
            else { granted = try await store().requestFullAccessToReminders() }
        } catch {
            requested.remove(kind)
            throw error
        }
        return granted
    }
    private func authorizedStore(_ kind: ScheduleItem.Kind) throws -> EKEventStore {
        guard EKEventStore.authorizationStatus(for: kind == .event ? .event : .reminder) == .fullAccess,
              let storage else { throw CalendarBridgeError.denied }
        return storage
    }
    private func find(_ item: ScheduleItem, in store: EKEventStore) throws -> EKCalendarItem? {
        guard let link = item.link else { return nil }
        if let kind = link.kind { _ = try authorizedStore(kind) }
        if let local = store.calendarItem(withIdentifier: link.localID),
           link.externalID == nil || local.calendarItemExternalIdentifier == link.externalID { return local }
        guard let external = link.externalID else { return nil }
        let candidates = store.calendarItems(withExternalIdentifier: external)
        guard candidates.count <= 1 else { throw CalendarBridgeError.ambiguous }
        return candidates.first
    }
    public func fetch(_ item: ScheduleItem) throws -> ScheduleItem? {
        let store = try authorizedStore(item.kind)
        guard let value = try find(item, in: store) else { return nil }
        return decoded(value, retaining: item)
    }
    private func decoded(_ value: EKCalendarItem, retaining item: ScheduleItem) -> ScheduleItem? {
        var result = item
        result.title = value.title ?? ""
        result.link = .init(localID: value.calendarItemIdentifier, externalID: value.calendarItemExternalIdentifier, kind: value is EKEvent ? .event : .reminder)
        result.modified = value.lastModifiedDate ?? item.modified
        if let event = value as? EKEvent {
            guard let start = event.startDate, let end = event.endDate else { return nil }
            result.start = start; result.end = end; result.isDateOnly = event.isAllDay
        } else if let reminder = value as? EKReminder {
            guard let due = reminder.dueDateComponents,
                  let date = (due.calendar ?? Calendar.current).date(from: due) else { return nil }
            result.start = date; result.end = nil; result.isDateOnly = due.hour == nil
            result.isCompleted = reminder.isCompleted
        }
        return result
    }
    public func save(_ item: ScheduleItem) throws -> ScheduleItem {
        if let end = item.end, end <= item.start { throw CalendarBridgeError.invalidDate }
        let store = try authorizedStore(item.kind)
        let existing = try find(item, in: store)
        let isSameKind = item.kind == .event ? existing is EKEvent : existing is EKReminder
        let value: EKCalendarItem
        if let existing, isSameKind { value = existing }
        else if item.kind == .event {
            let event = EKEvent(eventStore: store)
            guard let calendar = newItemCalendar(.event, in: store) else { throw CalendarBridgeError.noDefaultCalendar }
            event.calendar = calendar; value = event
        } else {
            let reminder = EKReminder(eventStore: store)
            guard let calendar = newItemCalendar(.reminder, in: store) else { throw CalendarBridgeError.noDefaultCalendar }
            reminder.calendar = calendar; value = reminder
        }
        guard value.calendar.allowsContentModifications else { throw CalendarBridgeError.readOnly }
        value.title = item.title
        if let event = value as? EKEvent {
            event.startDate = item.start; event.endDate = item.end; event.isAllDay = item.isDateOnly
            try store.save(event, span: .thisEvent, commit: true)
        } else if let reminder = value as? EKReminder {
            var parts = Calendar.current.dateComponents(item.isDateOnly ? [.year, .month, .day] : [.year, .month, .day, .hour, .minute], from: item.start)
            parts.calendar = Calendar.current
            parts.timeZone = Calendar.current.timeZone
            reminder.startDateComponents = parts
            reminder.dueDateComponents = parts
            reminder.isCompleted = item.isCompleted
            reminder.alarms = item.isDateOnly || item.isCompleted ? [] : [EKAlarm(absoluteDate: item.start)]
            try store.save(reminder, commit: true)
        }
        if let existing, !isSameKind {
            do { try removeValue(existing, in: store) }
            catch {
                let original = error
                do { try removeValue(value, in: store) }
                catch { throw NSError(domain: "Float.ScheduleConversion", code: 1, userInfo: [NSLocalizedDescriptionKey: "종류 변경 실패: \(original.localizedDescription), 새 항목 정리 실패: \(error.localizedDescription)"]) }
                throw original
            }
        }
        return decoded(value, retaining: item) ?? item
    }
    private func removeValue(_ value: EKCalendarItem, in store: EKEventStore) throws {
        guard value.calendar.allowsContentModifications else { throw CalendarBridgeError.readOnly }
        if let event = value as? EKEvent { try store.remove(event, span: .thisEvent, commit: true) }
        else if let reminder = value as? EKReminder { try store.remove(reminder, commit: true) }
    }
    public func remove(_ item: ScheduleItem) throws {
        let store = try authorizedStore(item.kind)
        if let value = try find(item, in: store) { try removeValue(value, in: store) }
    }
    public func stop() {
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil; onChange = nil; storage = nil
    }
    isolated deinit { if let observer { NotificationCenter.default.removeObserver(observer) } }
}
