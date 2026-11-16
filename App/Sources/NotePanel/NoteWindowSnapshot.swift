import CoreGraphics
import Models

/// 노트 창 하나의 지금 모습. 실행해서 확인할 때와 다른 기능이 창 자리를 알아야 할 때 쓴다.
public struct NoteWindowSnapshot: Hashable, Sendable {
    public let noteID: NoteID
    /// 화면 좌표의 창 틀(AppKit 좌표).
    public let frame: CGRect
    public let isPinned: Bool
    /// `NSWindow.Level`의 값. 핀이 켜져 있으면 `.floating`.
    public let level: Int
    public let isVisible: Bool
    public let isKey: Bool
    /// 호버로 나타나는 것이 보이는 상태인지.
    public let isHovered: Bool
    /// `CGWindowID`로 쓸 수 있는 창 번호.
    public let windowNumber: Int
    /// 저장하지 못하고 있으면 그 까닭.
    public let problem: String?
}
