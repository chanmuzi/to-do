import Foundation
import UserNotifications

public protocol AgentExpiryNotifying: Sendable {
    func notify(_ provider: AgentProvider, taskName: String) async throws
}

public struct SystemAgentExpiryNotifier: AgentExpiryNotifying {
    public static let category = "float.agent.expired"
    public static let action = "float.agent.reconnect"

    fileprivate static func registerCategories(in center: UNUserNotificationCenter) async {
        let reconnect = UNNotificationAction(identifier: action, title: "다시 로그인", options: [.foreground])
        let view = UNNotificationAction(identifier: "float.agent.view", title: "보기", options: [.foreground])
        let categories = [UNNotificationCategory(identifier: category, actions: [reconnect], intentIdentifiers: []),
                          UNNotificationCategory(identifier: AgentReplyNotification.category, actions: [view], intentIdentifiers: [])]
        let others = await center.notificationCategories().filter { existing in
            !categories.contains { $0.identifier == existing.identifier }
        }
        center.setNotificationCategories(Set(others + categories))
    }

    public func notify(_ provider: AgentProvider, taskName: String) async throws {
        let center = UNUserNotificationCenter.current()
        guard try await center.requestAuthorization(options: [.alert, .sound]) else { return }
        await Self.registerCategories(in: center)
        let content = UNMutableNotificationContent()
        content.title = (provider == .claude ? "Claude" : "Codex") + " 로그인이 만료됐어요"
        content.body = taskName
        content.categoryIdentifier = Self.category
        content.userInfo = ["floatAgent": provider.rawValue]
        content.sound = .default
        try await center.add(UNNotificationRequest(identifier: Self.category + "." + provider.rawValue, content: content, trigger: nil))
    }
}

/// 빈 표시 파일만 남겨 앱을 다시 시작해도 같은 만료를 반복해서 알리지 않는다.
public actor AgentExpiryNotifications {
    public static let shared = AgentExpiryNotifications(notifier: SystemAgentExpiryNotifier())
    private let notifier: any AgentExpiryNotifying
    public init(notifier: any AgentExpiryNotifying) { self.notifier = notifier }

    package func blocked(_ connection: AgentConnection, taskName: String) async throws {
        let marker = connection.config.appending(path: "float-expiry-notified")
        do { try Data().write(to: marker, options: .withoutOverwriting) }
        catch CocoaError.fileWriteFileExists { return }
        do { try await notifier.notify(connection.provider, taskName: taskName) }
        catch {
            try FileManager.default.removeItem(at: marker)
            throw error
        }
    }

    public func reconnected(_ connection: AgentConnection) throws {
        let marker = connection.config.appending(path: "float-expiry-notified")
        do { try FileManager.default.removeItem(at: marker) }
        catch CocoaError.fileNoSuchFile { }
    }
}

package struct AgentReplyNotification: Equatable, Sendable {
    fileprivate static let category = "float.agent.reply"
    package let conversation: UUID
    package let request: UUID
    package let title: String
    package let body: String

    package init(conversation: UUID, request: UUID, title: String, body: String) {
        self.conversation = conversation
        self.request = request
        self.title = title
        self.body = body
    }

    package func deliver() async throws -> Bool {
        let center = UNUserNotificationCenter.current()
        let permission = await center.notificationSettings().authorizationStatus
        guard permission == .authorized || permission == .provisional else { return false }
        await SystemAgentExpiryNotifier.registerCategories(in: center)
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.categoryIdentifier = Self.category
        content.userInfo = ["floatConversation": conversation.uuidString]
        try await center.add(UNNotificationRequest(identifier: Self.category + "." + request.uuidString,
                                                   content: content, trigger: nil))
        return true
    }
}
