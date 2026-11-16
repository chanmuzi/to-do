import Models

/// ⇥로 스페이스를 차례로 바꾼다(spec 7). 차례는 스페이스 목록 그대로이고, 마지막 다음은 "스페이스 없음"이다.
nonisolated enum CaptureSpaceCycle {
    static func next(after current: SpaceID?, in spaces: [Space], backward: Bool = false) -> SpaceID? {
        let stops: [SpaceID?] = spaces.map(\.id) + [nil]
        let index = stops.firstIndex(of: current) ?? stops.count - 1
        let step = backward ? stops.count - 1 : 1
        return stops[(index + step) % stops.count]
    }

    /// 캡처 바를 열 때의 스페이스: 지난번에 쓴 것이 아직 있으면 그것, 아니면 첫 스페이스.
    static func initial(remembered: SpaceID??, in spaces: [Space]) -> SpaceID? {
        if case .some(let last) = remembered, last == nil || spaces.contains(where: { $0.id == last }) {
            return last
        }
        return spaces.first?.id
    }
}
