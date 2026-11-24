import Foundation
import Models
import UserNotifications

@MainActor
public protocol ReminderNotifier: AnyObject {
    func schedule(_ item: ScheduleItem, noteID: NoteID, requestPermission: Bool) async throws
    func cancel(_ item: ScheduleItem, noteID: NoteID)
}

@MainActor
public final class FakeReminderNotifier: ReminderNotifier {
    public private(set) var pending: [String: ScheduleItem] = [:]
    public private(set) var permissionRequests = 0
    public init() {}
    public func schedule(_ item: ScheduleItem, noteID: NoteID, requestPermission: Bool) async throws {
        if requestPermission { permissionRequests += 1 }
        pending[item.id] = item
    }
    public func cancel(_ item: ScheduleItem, noteID: NoteID) { pending[item.id] = nil }
}

@MainActor
public final class SystemReminderNotifier: NSObject, ReminderNotifier, UNUserNotificationCenterDelegate {
    private var storage: UNUserNotificationCenter?
    package var openConversation: (@MainActor (UUID, UUID?) -> Void)?
    public var openAgent: (@MainActor (String) -> Void)?
    public func installDelegate() { _ = center() }
    public var openNote: (@MainActor (NoteID) -> Void)?
    public override init() { super.init() }
    private func center() -> UNUserNotificationCenter {
        if let storage { return storage }
        let value = UNUserNotificationCenter.current()
        value.delegate = self; storage = value
        return value
    }
    private func identifier(_ item: ScheduleItem, _ noteID: NoteID) -> String { "float.\(noteID.rawValue).\(item.id)" }
    public func schedule(_ item: ScheduleItem, noteID: NoteID, requestPermission: Bool) async throws {
        // 날짜만 있는 항목은 특정 시각의 알림을 임의로 만들지 않는다.
        guard !item.isDateOnly, !item.isCompleted, !item.isDeleted, item.start > Date() else {
            cancel(item, noteID: noteID); return
        }
        let center = center()
        let settings = await center.notificationSettings()
        if settings.authorizationStatus == .notDetermined {
            guard requestPermission else { return }
            guard try await center.requestAuthorization(options: [.alert, .sound]) else { throw CalendarBridgeError.denied }
        } else if settings.authorizationStatus != .authorized && settings.authorizationStatus != .provisional {
            throw CalendarBridgeError.denied
        }
        let content = UNMutableNotificationContent()
        content.title = item.title.isEmpty ? "리마인더" : item.title
        content.sound = .default
        content.userInfo = ["noteID": noteID.rawValue]
        let parts = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: item.start)
        let trigger = UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)
        try await center.add(UNNotificationRequest(identifier: identifier(item, noteID), content: content, trigger: trigger))
    }
    public func cancel(_ item: ScheduleItem, noteID: NoteID) {
        // 다른 기기에서 바뀐 항목도 지난 실행의 앱 알림을 취소한다.
        let center = center()
        center.removePendingNotificationRequests(withIdentifiers: [identifier(item, noteID)])
        center.removeDeliveredNotifications(withIdentifiers: [identifier(item, noteID)])
    }
    public nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        if let raw = response.notification.request.content.userInfo["floatConversation"] as? String,
           let id = UUID(uuidString: raw), response.actionIdentifier != UNNotificationDismissActionIdentifier {
            let proposal = (response.notification.request.content.userInfo["floatProposal"] as? String).flatMap(UUID.init(uuidString:))
            await MainActor.run { openConversation?(id, proposal) }
            return
        }
        if let provider = response.notification.request.content.userInfo["floatAgent"] as? String,
           response.actionIdentifier != UNNotificationDismissActionIdentifier {
            await MainActor.run { openAgent?(provider) }
            return
        }
        guard let raw = response.notification.request.content.userInfo["noteID"] as? String else { return }
        await MainActor.run { openNote?(NoteID(rawValue: raw)) }
    }
    public nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}
