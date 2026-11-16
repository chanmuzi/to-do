import Models

/// 노트 창이 내려간 뒤 키 입력을 누가 받을지(D-025).
///
/// 노트 창은 앱이 앞에 있지 않아도 키 창이 된다. 키 창이던 노트가 내려가면 시스템은 키 입력을 다른 앱에
/// 돌려주므로, 그 뒤의 ⌘Z(휴지통 되돌리기)나 ⌘`가 다른 앱으로 간다. 그래서 쓰던 흐름을 이어 준다.
enum KeyHandoff: Hashable {
    /// 아무것도 하지 않는다(키 창이 아니던 창이 내려갔거나, 닫기만 했고 남은 노트가 없다).
    case none
    /// 보이는 노트 가운데 가장 앞의 것이 키 창을 이어받는다.
    case makeKey(NoteID)
    /// 보이는 노트가 없다. 방금 휴지통으로 보낸 것을 ⌘Z로 되돌릴 수 있게 앱을 앞으로 가져온다
    /// (앱이 앞에 있으면 키 창이 없어도 앱 메뉴가 단축키를 받는다).
    case activateApp

    /// - Parameters:
    ///   - wasKey: 내려간 창이 키 창이었는지.
    ///   - nextVisible: 남은 노트 가운데 보이는 것 중 가장 앞.
    ///   - afterTrash: 휴지통으로 보내서 내려간 것인지(되돌릴 것이 생긴다).
    static func afterDiscarding(wasKey: Bool, nextVisible: NoteID?, afterTrash: Bool) -> KeyHandoff {
        guard wasKey else { return .none }
        if let nextVisible { return .makeKey(nextVisible) }
        return afterTrash ? .activateApp : .none
    }
}
