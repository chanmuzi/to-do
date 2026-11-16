import Foundation
import Models

/// 노트 창의 위치·크기·핀·열림 상태. 노트 파일과 따로 `stateDirectory/windows.json`에 둔다(D-003).
///
/// 값은 메모리에서 곧바로 바뀌고(`state(for:)`, `all`, `observe`가 그것을 본다), 파일에는 `writeDelay`가 지난 뒤
/// 한 번에 쓴다: 창 하나를 띄우거나 키 창이 될 때마다 잇달아 오는 변경(틀, 겹친 차례, 연 때)이 파일 전체를
/// 여러 번 다시 쓰지 않게 한다. 파일을 읽을 다른 쪽이 그 값을 봐야 할 때와 앱을 끝낼 때는 `flush()`를 부른다.
@MainActor
public final class WindowStateStore {
    /// 앱이 쓰는 기본 미루는 시간.
    public static let coalescingWriteDelay: Duration = .milliseconds(300)

    private let file: JSONFile<[String: NoteWindowState]>
    private var states: [String: NoteWindowState]
    private let observers = StateObservers()
    private let writeDelay: Duration
    /// 메모리의 값이 파일과 다르다(아직 쓰지 않았거나 쓰지 못했다).
    private var isDirty = false
    private var pendingWrite: Task<Void, Never>?
    /// 저장된 파일을 읽지 못해 빈 상태로 시작했으면 그 설명. 앱이 켤 때 모아서 기록한다.
    public let loadWarning: String?
    /// 미뤄 둔 쓰기가 실패했을 때 불린다. 값은 메모리에 남아 있고 다음 변경이나 `flush()` 때 다시 쓴다.
    public var onWriteFailure: (@MainActor (Error) -> Void)?
    /// 파일에 쓴 횟수(쓰기를 한데 모으는지 볼 때 쓴다).
    public private(set) var writeCount = 0

    /// 파일이 망가져 있으면 옆으로 옮겨 두고(`windows.json.corrupt`) 빈 상태로 시작한다.
    /// - Parameter writeDelay: 마지막 변경 뒤 파일에 쓰기까지 미루는 시간. 0이면 바꿀 때마다 곧바로 쓰고
    ///   실패를 그 자리에서 던진다.
    public init(location: StoreLocation, writeDelay: Duration = .zero) throws {
        file = JSONFile(url: location.stateDirectory.appendingPathComponent("windows.json"))
        let loaded = try file.loadRecovering()
        states = loaded.value ?? [:]
        loadWarning = loaded.warning
        self.writeDelay = writeDelay
    }

    public var all: [NoteID: NoteWindowState] {
        Dictionary(uniqueKeysWithValues: states.map { (NoteID(rawValue: $0.key), $0.value) })
    }

    public func state(for id: NoteID) -> NoteWindowState? {
        states[id.rawValue]
    }

    /// 바꾼다. 미루는 시간이 0이면 곧바로 파일에 쓰고, 아니면 잠시 뒤에 그사이의 변경과 함께 한 번 쓴다.
    public func set(_ state: NoteWindowState, for id: NoteID) throws {
        try commit(states.merging([id.rawValue: state]) { _, new in new })
    }

    public func remove(_ id: NoteID) throws {
        try commit(states.filter { $0.key != id.rawValue })
    }

    /// 창 상태가 바뀔 때마다 불린다. 돌려받은 값을 들고 있는 동안만 알림이 온다.
    /// 값이 그대로인 `set`은 쓰지도 알리지도 않는다. 무엇이 바뀌었는지는 `all`, `state(for:)`로 다시 읽는다.
    public func observe(_ handler: @escaping @MainActor () -> Void) -> StoreObservation {
        observers.add(handler)
    }

    /// 아직 쓰지 않은 변경을 지금 파일에 쓴다. 쓸 것이 없으면 아무것도 하지 않는다.
    /// 앱을 끝내기 전과, 파일을 직접 읽는 쪽이 지금 값을 봐야 할 때 부른다.
    public func flush() throws {
        pendingWrite?.cancel()
        pendingWrite = nil
        guard isDirty else { return }
        try file.save(states)
        writeCount += 1
        isDirty = false
    }

    private func commit(_ newStates: [String: NoteWindowState]) throws {
        guard newStates != states else { return }
        if writeDelay == .zero {
            // 쓰지 못하면 값도 바꾸지 않는다(부른 쪽이 실패를 받는다).
            try file.save(newStates)
            writeCount += 1
            states = newStates
        } else {
            states = newStates
            isDirty = true
            scheduleWrite()
        }
        observers.notify()
    }

    /// 마지막 변경 뒤 `writeDelay`가 지나면 쓴다. 그사이 변경이 또 오면 다시 잰다.
    private func scheduleWrite() {
        pendingWrite?.cancel()
        let delay = writeDelay
        pendingWrite = Task { [weak self] in
            guard (try? await Task.sleep(for: delay)) != nil, !Task.isCancelled else { return }
            self?.writePending()
        }
    }

    private func writePending() {
        pendingWrite = nil
        do {
            try flush()
        } catch {
            // 숨기지 않고 알린다. 값은 `isDirty`인 채 남아 다음 변경이나 `flush()`가 다시 쓴다.
            onWriteFailure?(error)
        }
    }
}
