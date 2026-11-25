import Foundation
import Models
import Store

/// 한 번에 한 항목씩 동기화한다. await 뒤에는 파일의 최신 항목을 다시 확인해 편집 중인 글을 덮지 않는다.
@MainActor
public final class ScheduleService {
    private let notes: any NoteStoring
    private let makeBridge: @MainActor () -> any CalendarBridge
    private let notifier: any ReminderNotifier
    private let log: @MainActor (String) -> Void
    private var bridgeStorage: (any CalendarBridge)?
    private var observation: StoreObservation?
    private var known: [NoteID: Note] = [:]
    private var pending: Set<NoteID> = []
    private var registrations: [NoteID: [String: Bool]] = [:]
    private var worker: Task<Void, Never>?
    private var writing = false
    private var lastTrashRemoval: (id: NoteID, kinds: [ScheduleItem.Kind])?

    package func removedFromTrashMove(_ id: NoteID) -> [ScheduleItem.Kind] {
        lastTrashRemoval?.id == id ? lastTrashRemoval?.kinds ?? [] : []
    }

    public init(notes: any NoteStoring, notifier: any ReminderNotifier,
                makeBridge: @escaping @MainActor () -> any CalendarBridge,
                log: @escaping @MainActor (String) -> Void = { _ in }) {
        self.notes = notes; self.notifier = notifier; self.makeBridge = makeBridge; self.log = log
    }
    public func start() throws {
        known = Dictionary(uniqueKeysWithValues: try notes.list().notes.map { ($0.id, $0) })
        observation = notes.observe { [weak self] change in
            guard let self, !writing else { return }
            switch change.kind {
            case .created, .updated:
                if let previous = known[change.id], let current = try? notes.load(change.id),
                   previous.body == current.body, previous.schedules != current.schedules,
                   previous.schedules.map(\.calendarFields) == current.schedules.map(\.calendarFields) {
                    known[change.id] = current
                } else {
                    enqueue(change.id)
                }
            case .removed:
                pending.remove(change.id)
                registrations[change.id] = nil
                let items = change.trashedSchedules ?? known[change.id]?.schedules ?? []
                items.forEach { notifier.cancel($0, noteID: change.id) }
                if change.trashedSchedules != nil {
                    lastTrashRemoval = (change.id, removeTrashedLinks(change.id, items: items))
                }
                known[change.id] = nil
            case .conflict, .saveFailed: break
            }
        }
        // 과거 사용한 연결은 권한 요청 없이 재개한다. 빈 앱은 bridge를 만들지도 않는다.
        try retryTrashedLinks()
        for note in known.values where !note.schedules.isEmpty { enqueue(note.id) }
    }
    private func retryTrashedLinks() throws {
        for note in try notes.listTrash().notes {
            _ = removeTrashedLinks(note.id, items: note.schedules)
        }
    }

    private func removeTrashedLinks(_ id: NoteID, items: [ScheduleItem]) -> [ScheduleItem.Kind] {
        guard items.contains(where: { $0.trashState == .pendingRemoval }) else { return [] }
        var removed: [ScheduleItem.Kind] = []
        do {
            try notes.updateTrashSchedules(id) { values in
                for index in values.indices {
                    let item = values[index]
                    guard item.trashState == .pendingRemoval, let link = item.link,
                          !item.isDeleted, !item.isCompleted else { continue }
                    let kind = link.kind ?? item.kind
                    guard bridge.access(for: kind) == .available else { continue }
                    do {
                        let destination = bridge.destination(for: item)?.calendarID
                        let didRemove = try bridge.remove(item)
                        values[index].link = nil
                        values[index].syncedAt = nil
                        values[index].syncBaseline = nil
                        values[index].syncError = nil
                        values[index].pendingCalendarID = item.pendingCalendarID ?? destination
                        values[index].trashState = .removed
                        if didRemove { removed.append(kind) }
                    } catch {
                        values[index].syncError = error.localizedDescription
                        log("휴지통 예정 삭제 대기 \(item.id): \(error)")
                    }
                }
            }
        } catch { log("휴지통 예정 기록 실패 \(id): \(error)") }
        return removed
    }

    private var bridge: any CalendarBridge {
        if let bridgeStorage { return bridgeStorage }
        let value = makeBridge()
        value.preferredID = preferredID
        value.onChange = { [weak self] in
            self?.refreshLinked()
            self?.calendarChanged?()
        }
        bridgeStorage = value
        return value
    }
    public var preferredID: (ScheduleItem.Kind) -> String? = { _ in nil } {
        didSet { bridgeStorage?.preferredID = preferredID }
    }
    public func calendarAccess(_ kind: ScheduleItem.Kind) -> CalendarAccess { bridge.access(for: kind) }
    public func calendarChoices(_ kind: ScheduleItem.Kind) -> [CalendarChoice] { bridge.writableChoices(for: kind) }
    public func systemDefault(_ kind: ScheduleItem.Kind) -> ScheduleDestination? { bridge.systemDefault(for: kind) }
    public func connect(_ kind: ScheduleItem.Kind) async throws {
        guard bridge.access(for: kind) == .needsRequest else { return }
        _ = try await bridge.authorize(kind, request: true)
    }
    public var calendarChanged: (() -> Void)?
    public func events(in interval: DateInterval) -> [CalendarEvent] { bridge.events(in: interval) }
    package func todayContext(now: Date, calendar: Calendar) async -> TodayScheduleContext {
        var result = TodayScheduleContext()
        guard let day = calendar.dateInterval(of: .day, for: now),
              let snapshot = try? notes.list().notes else { return result }
        result.events = TodayScheduleContext.section(kind: .event, selection: await bridge.contextItems(.event, day: day),
                                                    notes: snapshot, day: day, now: now, calendar: calendar)
        result.reminders = TodayScheduleContext.section(kind: .reminder, selection: await bridge.contextItems(.reminder, day: day),
                                                       notes: snapshot, day: day, now: now, calendar: calendar)
        return result
    }
    public func destination(for item: ScheduleItem) -> ScheduleDestination? { bridge.destination(for: item) }
    public func refreshLinked() {
        do {
            try retryTrashedLinks()
            for note in try notes.list().notes where note.schedules.contains(where: { $0.link != nil || $0.trashState != nil }) {
                enqueue(note.id)
            }
        } catch { log("예정 다시 읽기 실패: \(error)") }
    }
    /// 설정 저장/빠른 캡처가 저장에 성공한 항목만 명시한다. 일반 저장 이벤트는 이 경로를 쓰지 않는다.
    public func register(_ id: NoteID, itemID: String, requestPermission: Bool) {
        registrations[id, default: [:]][itemID] = (registrations[id]?[itemID] ?? false) || requestPermission
        enqueue(id)
    }
    public func enqueue(_ id: NoteID) {
        pending.insert(id)
        guard worker == nil else { return }
        worker = Task { [weak self] in await self?.drain() }
    }
    public func flush() async {
        while let worker { await worker.value }
    }
    private func drain() async {
        while let id = pending.first, !Task.isCancelled {
            pending.remove(id)
            let intents = registrations.removeValue(forKey: id) ?? [:]
            do { try await synchronize(id, intents: intents) }
            catch { log("예정 동기화 실패 \(id): \(error)") }
        }
        worker = nil
    }
    private func synchronize(_ id: NoteID, intents: [String: Bool]) async throws {
        var note = try notes.load(id)
        let currentIDs = Set(note.schedules.map(\.id))
        for removed in known[id]?.schedules ?? [] where !currentIDs.contains(removed.id) {
            notifier.cancel(removed, noteID: id)
        }
        let previousSchedules = note.schedules
        do {
            for index in note.schedules.indices where note.schedules[index].kind == .reminder {
                guard let anchor = note.schedules[index].todo,
                      let completed = anchor.completed(in: note.body),
                      completed != note.schedules[index].isCompleted else { continue }
                note.schedules[index].isCompleted = completed
                note.schedules[index].modified = Date()
            }
            if previousSchedules != note.schedules {
                let updated = note.schedules
                try write(id) { $0.schedules = updated }
            }
        }
        known[id] = note
        for expected in note.schedules {
            guard !Task.isCancelled else { return }
            // 이전 항목의 저장 중 들어온 편집을 버리지 않는다.
            guard try notes.load(id).schedules.first(where: { $0.id == expected.id }) == expected else {
                if let request = intents[expected.id] { register(id, itemID: expected.id, requestPermission: request) }
                else { enqueue(id) }
                continue
            }
            let isNew = expected.link == nil || expected.link?.kind != expected.kind
            let allowPrompt = intents[expected.id] == true && isNew && !expected.isDeleted && expected.trashState == nil
            // 연결 없는 삭제는 로컬에서 끝낸다. 권한이 없어도 삭제 대기를 남길 필요가 없다.
            if expected.isDeleted && expected.link == nil {
                notifier.cancel(expected, noteID: id)
                try replace(expected, with: nil, in: id)
                continue
            }
            if expected.trashState != nil && expected.link == nil && !expected.isUpcoming(at: Date()) { continue }
            if expected.link == nil && expected.id.hasPrefix("legacy-") && expected.trashState != .removed {
                // 옛 항목은 이미 권한이 있어도 그 항목을 열어 저장한 경우에만 이관한다.
                guard intents[expected.id] != nil, expected.isUpcoming(at: Date()) else { continue }
            }
            do {
                if let linkedKind = expected.link?.kind, linkedKind != expected.kind {
                    guard try await bridge.authorize(linkedKind, request: false) else { continue }
                }
                // 권한 없음은 연동 실패가 아니다. 파일과 앱 알림 권한을 건드리지 않는다.
                guard try await bridge.authorize(expected.kind, request: allowPrompt) else {
                    if expected.trashState != nil, expected.link == nil,
                       !expected.isDateOnly, expected.isUpcoming(at: Date()),
                       try notes.load(id).schedules.contains(expected) {
                        try await notifier.schedule(expected, noteID: id, requestPermission: false)
                        if (try? notes.load(id).schedules.contains(expected)) != true {
                            notifier.cancel(expected, noteID: id)
                        }
                    }
                    continue
                }
            } catch {
                // 권한 API의 오류도 실제 등록 시도 실패와 구분한다.
                log("예정 권한 확인 실패 \(expected.id): \(error.localizedDescription)")
                continue
            }
            do {
                guard try notes.load(id).schedules.first(where: { $0.id == expected.id }) == expected else {
                    if let request = intents[expected.id] { register(id, itemID: expected.id, requestPermission: request) }
                    else { enqueue(id) }
                    continue
                }
                if expected.isDeleted {
                    if expected.link != nil { try bridge.remove(expected) }
                    notifier.cancel(expected, noteID: id)
                    try replace(expected, with: nil, in: id)
                    continue
                }
                if expected.link != nil {
                    guard let remote = try bridge.fetch(expected.calendarFields) else {
                        notifier.cancel(expected, noteID: id)
                        if expected.trashState == .pendingRemoval {
                            // 이전 실행이 외부 삭제 뒤 파일에 결과를 쓰기 전에 끝났다.
                            var detached = expected
                            detached.link = nil
                            detached.trashState = .removed
                            try replace(expected, with: detached, in: id)
                            enqueue(id)
                        } else { try replace(expected, with: nil, in: id) }
                        continue
                    }
                    let baseline = expected.syncedAt ?? .distantPast
                    let remoteChanged = expected.syncBaseline.map { $0 != remote.value } ?? (remote.modified > baseline)
                    let localChanged = expected.pendingCalendarID != nil || (expected.syncBaseline.map { $0 != expected.value } ?? (expected.modified > baseline))
                    if remoteChanged && localChanged { log("예정 충돌 \(expected.id): 마지막 수정 시각으로 선택") }
                    if remoteChanged && (!localChanged || remote.modified > expected.modified) {
                        var received = remote
                        received.syncedAt = max(Date(), remote.modified)
                        received.pendingCalendarID = nil
                        received.syncBaseline = remote.value
                        received.syncError = nil
                        try replace(expected, with: received, in: id, updateTodo: true)
                        notifier.cancel(expected, noteID: id)
                        continue
                    }
                    if !localChanged {
                        if expected.syncError != nil || expected.link != remote.link || expected.trashState != nil {
                            var recovered = expected; recovered.syncError = nil; recovered.link = remote.link; recovered.trashState = nil
                            try replace(expected, with: recovered, in: id)
                        }
                        notifier.cancel(expected, noteID: id)
                        continue
                    }
                }
                var saved = try bridge.save(expected.calendarFields)
                saved.syncedAt = max(Date(), saved.modified)
                saved.pendingCalendarID = nil
                saved.syncBaseline = saved.value
                saved.syncError = nil
                try replace(expected, with: saved, in: id)
                notifier.cancel(expected, noteID: id)
            } catch CalendarBridgeError.denied {
                // 확인 뒤 접근이 철회된 경우도 로컬 값을 보존한다.
                log("예정 접근이 허용되지 않음 \(expected.id)")
            } catch {
                log("예정 연동 실패 \(expected.id): \(error.localizedDescription)")
                var failed = expected; failed.syncError = error.localizedDescription
                try replace(expected, with: failed, in: id)
                // 연결된 항목의 일시적 오류는 Apple 알림과 중복시키지 않는다.
                if expected.link == nil && !expected.isDeleted && !expected.isCompleted && !expected.isDateOnly && expected.start > Date() {
                    do { try await notifier.schedule(expected, noteID: id, requestPermission: allowPrompt) }
                    catch { log("앱 알림 실패 \(expected.id): \(error.localizedDescription)") }
                    let latest = try? notes.load(id).schedules.first { $0.id == expected.id }
                    if latest != failed { notifier.cancel(expected, noteID: id); if latest != nil { enqueue(id) } }
                } else { notifier.cancel(expected, noteID: id) }
            }
        }
        known[id] = try notes.load(id)
    }
    private func replace(_ expected: ScheduleItem, with replacement: ScheduleItem?, in id: NoteID, updateTodo: Bool = false) throws {
        try write(id) { current in
            guard let index = current.schedules.firstIndex(where: { $0.id == expected.id }),
                  current.schedules[index] == expected else { return }
            if var replacement {
                replacement.imminentLeadMinutes = expected.imminentLeadMinutes
                current.schedules[index] = replacement
                if updateTodo, replacement.kind == .reminder, replacement.isCompleted != expected.isCompleted,
                   let todo = expected.todo { current.body = todo.settingCompleted(replacement.isCompleted, in: current.body) }
            } else { current.schedules.remove(at: index) }
        }
    }
    private func write(_ id: NoteID, _ mutate: (inout Note) -> Void) throws {
        writing = true
        defer { writing = false }
        try notes.update(id, mutate)
    }
    public func stop() {
        observation?.cancel(); observation = nil
        worker?.cancel(); worker = nil
        bridgeStorage?.stop(); pending.removeAll(); registrations.removeAll()
    }
}

private extension ScheduleItem {
    /// 임박 표시는 노트 파일에만 속한다. 외부 동기화와 변경 감지에는 전달하지 않는다.
    var calendarFields: ScheduleItem {
        var item = self
        item.imminentLeadMinutes = nil
        item.trashState = nil
        return item
    }
}
