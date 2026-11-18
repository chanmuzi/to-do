import Foundation
import Models
import Observation
import Scheduling
import Theme

package enum SettingsPane: String, CaseIterable {
    case general = "일반", appearance = "모양", editor = "편집기", schedule = "일정과 캘린더"
    case shortcuts = "단축키", assistant = "AI 비서", accounts = "엔진과 계정", about = "앱 정보"

    var summary: String {
        switch self {
        case .general: "Mac에서 Float를 사용하는 방법"
        case .appearance: "노트의 화면과 본문 글자 모양"
        case .editor: "노트 본문을 쓰고 고칠 때의 모양과 도움 기능"
        case .schedule: "일정을 표시하는 방법과 새 일정을 저장할 곳"
        case .shortcuts: "Float에서 사용할 수 있는 단축키"
        case .assistant: "Float에서 사용할 엔진과 모델"
        case .accounts: "Float 전용 폴더에서 엔진별 계정을 연결해요"
        case .about: "설치한 Float 버전과 설정 초기화"
        }
    }
}

package struct ShortcutSection: Identifiable {
    package var id: String { title }
    let title: String
    let rows: [(action: String, keys: String)]
    package init(_ title: String, rows: [(String, String)]) {
        self.title = title
        self.rows = rows
    }
}

struct DestinationMenu {
    let access: CalendarAccess
    let choices: [CalendarChoice]
    let system: ScheduleDestination?
}

@Observable
package final class SettingsModel {
    package var pane = SettingsPane.general
    package let agents: AgentSettings?
    package let shortcuts: [ShortcutSection]
    private let read: () -> SettingsValues
    private let save: ((inout SettingsValues) -> Void) throws -> Void
    private let schedules: ScheduleService
    let openPrivacy: (ScheduleItem.Kind) -> Void
    var menus: [ScheduleItem.Kind: DestinationMenu] = [:]
    private(set) var connecting = false
    package private(set) var error: String?
    package var values: SettingsValues { read() }

    package init(read: @escaping () -> SettingsValues, save: @escaping ((inout SettingsValues) -> Void) throws -> Void,
                 schedules: ScheduleService, shortcuts: [ShortcutSection], agents: AgentSettings? = nil, openPrivacy: @escaping (ScheduleItem.Kind) -> Void) {
        self.agents = agents
        self.read = read
        self.save = save
        self.schedules = schedules
        self.shortcuts = shortcuts
        self.openPrivacy = openPrivacy
    }

    @discardableResult
    package func change(_ mutation: (inout SettingsValues) -> Void) -> Bool {
        do {
            try save(mutation)
            error = nil
            return true
        } catch {
            self.error = error.localizedDescription
            return false
        }
    }

    func restoreDefaults(theme: Theme) {
        let prior = theme.overrides
        do {
            if !prior.isEmpty { try theme.setOverrides(ThemeOverrides()) }
            do { try save { $0 = SettingsValues() } }
            catch {
                if !prior.isEmpty { try theme.setOverrides(prior) }
                throw error
            }
            error = nil
            refreshCalendars()
        } catch { self.error = error.localizedDescription }
    }

    package func refreshCalendars() {
        for kind in [ScheduleItem.Kind.event, .reminder] {
            let access = schedules.calendarAccess(kind)
            let choices = access == .available ? schedules.calendarChoices(kind) : []
            menus[kind] = DestinationMenu(access: access, choices: choices,
                system: access == .available ? schedules.systemDefault(kind) : nil)
            if access == .available, let id = values[idFor: kind], !choices.contains(where: { $0.id == id }) {
                change { $0[idFor: kind] = nil }
            }
        }
    }

    package func choose(_ id: String?, for kind: ScheduleItem.Kind) {
        guard let menu = menus[kind], menu.access == .available,
              id == nil || menu.choices.contains(where: { $0.id == id }) else { return }
        change { $0[idFor: kind] = id }
    }

    package func connectRequestedCalendars() async {
        for kind in [ScheduleItem.Kind.event, .reminder] where schedules.calendarAccess(kind) == .needsRequest {
            await connect(kind)
        }
    }

    package func connect(_ kind: ScheduleItem.Kind) async {
        guard !connecting, schedules.calendarAccess(kind) == .needsRequest else { return }
        connecting = true
        defer { connecting = false }
        do { try await schedules.connect(kind) }
        catch { if schedules.calendarAccess(kind) != .blocked { self.error = error.localizedDescription } }
        refreshCalendars()
    }
}

extension SettingsValues {
    package subscript(idFor kind: ScheduleItem.Kind) -> String? {
        get { kind == .event ? calendarID : reminderListID }
        set {
            if kind == .event { calendarID = newValue }
            else { reminderListID = newValue }
        }
    }
}
