import Models

/// 떠 있는 노트를 창 상태에서 고른다. 앞에 있는 창(겹친 차례가 큰 것)이 먼저다.
nonisolated enum BrowseFloating {
    static func ids(from states: [NoteID: NoteWindowState]) -> [NoteID] {
        states
            .filter(\.value.isOpen)
            .sorted { first, second in
                let orders = (first.value.stackOrder ?? Int.min, second.value.stackOrder ?? Int.min)
                return orders.0 != orders.1 ? orders.0 > orders.1 : first.key.rawValue < second.key.rawValue
            }
            .map(\.key)
    }
}
