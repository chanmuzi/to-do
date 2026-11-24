import AgentRunner
import Foundation
import Theme

/// 설정 창과 앱이 공유하는 저장 형식.
package nonisolated struct SettingsValues: Codable, Equatable, Sendable {
    /// 메뉴 막대 아이콘을 보일지. 시안대로 기본은 보임이다(임시 값, D-024).
    /// 꺼도 모든 기능은 전역 단축키, 앱 메뉴, Dock 메뉴로 쓸 수 있다.
    package var showsMenuBarIcon = true
    /// 본문 편집기의 표시 방식(spec 6). 값은 `tokens.json`의 `display`에 적힌 이름이다
    /// (`inline-code`: `accent` | `plain`, `checkbox`: `box` | `bracket`). 모르는 이름은 기본값으로 읽는다
    /// (`NoteEditorOptions(settings:)`).
    package var inlineCode = "accent"
    package var checkbox = "box"
    package var spaceDisplay = "icon"
    package var reminderDisplay = "time"
    package var clockFormat = "koreanMeridiem"
    package var showsNoteAgent = true
    package var showsCornerAgent = false
    package var agentProvider = "claude"
    package var codexModel: String?
    package var claudeEffort: String?
    package var codexEffort: String?
    package var effort: String? {
        get { agentProvider == "codex" ? codexEffort : claudeEffort }
        set {
            if agentProvider == "codex" { codexEffort = newValue }
            else { claudeEffort = newValue }
        }
    }
    package var agentModel = "auto"
    package var noteHeightMode: NoteDisplayOptions.HeightMode = .fixed
    package var appearance = "system"
    package var bodySize: Int?
    package var bodyLineHeight: Int?
    package enum MarkedTextStyle: String, Codable, Sendable { case none, underline }
    package var markedTextStyle: MarkedTextStyle = .none
    package var showsFormatBar = false
    private enum LegacyKeys: String, CodingKey { case formatBar }
    package var recognizesDates = true
    package var calendarID: String?
    package var reminderListID: String?
    package var scheduleDateFormat = "relative"

    package init(showsMenuBarIcon: Bool = true, inlineCode: String = "accent", checkbox: String = "box", scheduleDateFormat: String = "relative") {
        self.showsMenuBarIcon = showsMenuBarIcon
        self.inlineCode = inlineCode
        self.checkbox = checkbox
        self.scheduleDateFormat = scheduleDateFormat
    }

    package func selectedEngine(codexModels: [CodexModel]) -> AgentEngine {
        if agentProvider == "codex" {
            return .codex(model: codexModels.first { $0.slug == codexModel }?.slug)
        }
        return .claude(agentModel)
    }

    /// 나중에 더한 항목이 없는 예전 파일도 읽는다(없는 항목은 기본값).
    package init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        showsNoteAgent = try container.decodeIfPresent(Bool.self, forKey: .showsNoteAgent) ?? true
        showsCornerAgent = try container.decodeIfPresent(Bool.self, forKey: .showsCornerAgent) ?? false
        agentProvider = try container.decodeIfPresent(String.self, forKey: .agentProvider) ?? "claude"
        claudeEffort = try container.decodeIfPresent(String.self, forKey: .claudeEffort)
        codexEffort = try container.decodeIfPresent(String.self, forKey: .codexEffort)
        codexModel = try container.decodeIfPresent(String.self, forKey: .codexModel)
        agentModel = try container.decodeIfPresent(String.self, forKey: .agentModel) ?? "auto"
        spaceDisplay = try container.decodeIfPresent(String.self, forKey: .spaceDisplay) ?? "icon"
        reminderDisplay = try container.decodeIfPresent(String.self, forKey: .reminderDisplay) ?? "time"
        clockFormat = try container.decodeIfPresent(String.self, forKey: .clockFormat) ?? "koreanMeridiem"
        let height = try container.decodeIfPresent(String.self, forKey: .noteHeightMode)
        noteHeightMode = height.flatMap(NoteDisplayOptions.HeightMode.init(rawValue:)) ?? .fixed
        appearance = try container.decodeIfPresent(String.self, forKey: .appearance) ?? "system"
        bodySize = try container.decodeIfPresent(Int.self, forKey: .bodySize)
        bodyLineHeight = try container.decodeIfPresent(Int.self, forKey: .bodyLineHeight)
        let markedStyle = try container.decodeIfPresent(String.self, forKey: .markedTextStyle)
        markedTextStyle = markedStyle.flatMap(MarkedTextStyle.init(rawValue:)) ?? .none
        if let enabled = try container.decodeIfPresent(Bool.self, forKey: .showsFormatBar) {
            showsFormatBar = enabled
        } else {
            let legacy = try decoder.container(keyedBy: LegacyKeys.self)
            showsFormatBar = try legacy.decodeIfPresent(String.self, forKey: .formatBar) == "always"
        }
        recognizesDates = try container.decodeIfPresent(Bool.self, forKey: .recognizesDates) ?? true
        calendarID = try container.decodeIfPresent(String.self, forKey: .calendarID)
        reminderListID = try container.decodeIfPresent(String.self, forKey: .reminderListID)
        showsMenuBarIcon = try container.decodeIfPresent(Bool.self, forKey: .showsMenuBarIcon) ?? true
        inlineCode = try container.decodeIfPresent(String.self, forKey: .inlineCode) ?? "accent"
        scheduleDateFormat = try container.decodeIfPresent(String.self, forKey: .scheduleDateFormat) ?? "relative"
        checkbox = try container.decodeIfPresent(String.self, forKey: .checkbox) ?? "box"
    }
}
