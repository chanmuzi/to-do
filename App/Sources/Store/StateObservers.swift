import Foundation

/// 작은 상태 저장소(`WindowStateStore`, `SpaceStore`)가 "바뀌었다"를 알리는 곳.
/// 무엇이 바뀌었는지는 싣지 않는다. 받는 쪽이 지금 값을 다시 읽는다.
@MainActor
final class StateObservers {
    private var handlers: [UUID: @MainActor () -> Void] = [:]

    func add(_ handler: @escaping @MainActor () -> Void) -> StoreObservation {
        let token = UUID()
        handlers[token] = handler
        return StoreObservation { [weak self] in self?.handlers[token] = nil }
    }

    /// 알리는 도중에 걸거나 푼 것은 다음 알림부터 따른다.
    func notify() {
        handlers.values.forEach { $0() }
    }
}
