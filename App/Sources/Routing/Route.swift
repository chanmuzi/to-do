import Models

/// 기능이 다른 기능에게 부탁하는 일. 기능 모듈은 서로를 import하지 않고 이 값만 보낸다.
public enum Route: Hashable, Sendable {
    /// 노트 창을 띄운다(이미 떠 있으면 앞으로 가져온다).
    case openNote(NoteID)
    /// 새 노트를 만들어 띄운다.
    case newNote(NewNoteRequest)
    /// 노트 창만 닫는다. 노트는 남는다.
    case closeNoteWindow(NoteID)
    /// 빠른 캡처 바.
    case openCapture
    /// 노트 찾기. `anchor`가 있으면 그 노트 상단 줄 아래에, 없으면 화면 가운데 위쪽에 뜬다(spec 4.1, D-030).
    case openBrowse(anchor: NoteID?)
    /// 떠 있는 노트를 모두 숨기거나 되돌린다.
    case toggleAllNotesHidden
    /// 닫은 노트를 다시 여는 라이브러리.
    case openLibrary
    // 아래의 AI, 설정, 리마인더 화면은 뒤 단계에서 연결한다.
    case openAIPanel(context: NoteID?)
    case openSettings
    case openShortcuts
    /// 노트의 리마인더를 정하는 화면(Reminders 단계).
    case openReminderEditor(NoteID)
    /// 노트를 다른 스페이스로 옮기는 고르기(Library 단계).
    case openSpacePicker(NoteID)
}

/// 새 노트 요청.
public struct NewNoteRequest: Hashable, Sendable {
    public var draft: NoteDraft
    /// 이 노트 옆에 띄운다(spec 4.1: 새 노트는 지금 노트 옆). 없으면 App이 자리를 정한다.
    public var nextTo: NoteID?

    public init(draft: NoteDraft = NoteDraft(), nextTo: NoteID? = nil) {
        self.draft = draft
        self.nextTo = nextTo
    }
}
