import Foundation

/// 한 실행에 필요한 로컬 보기 상태만 전달한다.
package struct AgentNoteContext: Codable {
    package static let filename = ".note-context.json"
    package struct Window: Codable {
        package var open: Bool
        package var pinned: Bool
        package init(_ state: NoteWindowState) {
            open = state.isOpen
            pinned = state.isPinned
        }
    }
    package var windows: [String: Window]
    package var spaces: [String: String]
    package var archiveCutoff: Date

    package init(windows: [String: Window], spaces: [String: String], archiveCutoff: Date) {
        self.windows = windows
        self.spaces = spaces
        self.archiveCutoff = archiveCutoff
    }
}
