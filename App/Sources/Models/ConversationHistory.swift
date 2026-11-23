import Foundation

/// 목록에는 첫 요청을 보낸 대화만 포함한다. 열람 시각은 정렬 기준에서 제외한다.
package struct ConversationDay: Identifiable {
    package let id: Date
    package let conversations: [AgentConversation]

    package static func sections(_ conversations: [AgentConversation], calendar: Calendar) -> [Self] {
        let groups = Dictionary(grouping: conversations.filter { !$0.requests.isEmpty }) {
            calendar.startOfDay(for: $0.updatedAt)
        }
        return groups.keys.sorted(by: >).map { day in
            Self(id: day, conversations: groups[day, default: []].sorted {
                ($0.updatedAt, $0.id.uuidString) > ($1.updatedAt, $1.id.uuidString)
            })
        }
    }
}
