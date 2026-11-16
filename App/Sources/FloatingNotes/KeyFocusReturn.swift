import Models

/// 캡처 바나 노트 찾기가 키 창을 잠깐 가져갔다가 닫힐 때, 키 입력을 어디로 돌려줄지(D-032).
///
/// 열 때 키 창이던 노트를 적어 두고, 닫힐 때 그 노트를 내준다. 열 때 키 창인 노트가 없었으면 돌려줄 곳이
/// 없다: 아무 노트도 키 창으로 만들지 않는다(노트 창은 저절로 키 창이 되지 않는다, D-025).
/// 한 번 내주면 비워서 같은 노트에게 두 번 돌려주지 않는다.
struct KeyFocusReturn: Equatable {
    private(set) var rememberedNote: NoteID?

    /// 화면을 연다. 지금 키 창인 노트를 적어 둔다.
    mutating func begin(keyNote: NoteID?) {
        rememberedNote = keyNote
    }

    /// 화면이 닫혔다.
    /// - Parameter returnsFocus: 포커스를 열기 전의 자리로 돌려줄 때인지. 바깥을 눌렀거나 다른 노트를
    ///   열도록 요청을 보냈으면 거짓이다(포커스가 갈 곳이 따로 있다).
    /// - Returns: 다시 키 창이 될 노트. 돌려줄 때가 아니거나 적어 둔 노트가 없으면 `nil`.
    mutating func end(returnsFocus: Bool) -> NoteID? {
        defer { rememberedNote = nil }
        return returnsFocus ? rememberedNote : nil
    }
}
