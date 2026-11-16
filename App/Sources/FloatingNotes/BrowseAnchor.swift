import AppKit
import Models

/// 노트 찾기를 어디에 붙이고 어느 노트를 목록에서 뺄지(spec 4.1, D-027의 6번).
enum BrowseAnchor {
    struct Placement {
        /// 이 창의 상단 줄 아래에 붙인다. 없으면 화면 가운데 위쪽에 띄운다.
        let window: NSWindow?
        /// 목록에서 뺄 노트(노트 찾기를 연 그 노트).
        let excluded: NoteID?
    }

    /// 붙일 노트의 창이 보이면 그 창에 붙이고 그 노트를 뺀다. 노트를 주지 않았거나 그 창이 없거나
    /// 보이지 않으면(닫힘, "노트 모두 숨기기") 붙이지 않고 아무 노트도 빼지 않는다: 화면에 없는 노트는
    /// 목록에서 찾아갈 수 있어야 한다.
    static func resolve(_ anchor: NoteID?, window: (NoteID) -> NSWindow?) -> Placement {
        guard let anchor, let window = window(anchor), window.isVisible else {
            return Placement(window: nil, excluded: nil)
        }
        return Placement(window: window, excluded: anchor)
    }
}
