import AppKit
import Foundation
import Observation
import Models
import Routing
import SpaceIcons
import Store
import Theme

@Observable
public final class LibraryModel {
    public let theme: Theme
    public let spaces: SpaceStore
    public let preferences: LibraryPreferencesStore
    public let router: any Routing
    private let notes: any NoteStoring
    private let windows: WindowStateStore
    public private(set) var index = LibraryIndex(notes: [])
    public private(set) var spaceList: [Space] = []
    public var selection: LibrarySelection = .today
    public private(set) var selectedNoteID: NoteID?
    public var displayOptions = NoteDisplayOptions()
    public var error: String?
    public var settings: LibraryPreferences { preferences.value }
    package var conversations: () -> [AgentConversation] = { [] }
    package var openConversation: (UUID) -> Void = { _ in }
    package var newConversation: () -> Void = {}
    package var selectedConversation: UUID?
    #if DEBUG
    package var previewHistoryHover: UUID?
    package var previewSectionHover = false
    #endif
    var expanded: Set<SpaceID> = []
    var iconSpace: SpaceID?
    package var editingViews = false
    public private(set) var editingSpace = false
    public private(set) var renamingSpaceID: SpaceID?
    static let defaultSpaceIcon = SpaceIcon.symbol(name: "folder", colorID: nil)
    var draftIcon = defaultSpaceIcon
    var choosingDraftIcon = false
    var draftFocus = 0
    @ObservationIgnored weak var spaceInputView: NSView?
    public var spaceName = ""
    public func beginSpaceEditing(_ id: SpaceID? = nil) {
        draftIcon = id.flatMap { spaces.space(for: $0)?.icon } ?? Self.defaultSpaceIcon
        choosingDraftIcon = false
        renamingSpaceID = id; spaceName = id.flatMap { spaces.space(for: $0)?.name } ?? ""; editingSpace = true
    }
    public func cancelSpaceEditing() { editingSpace = false; choosingDraftIcon = false; renamingSpaceID = nil; spaceName = "" }
    public func submitSpaceEditing() {
        let value = spaceName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        do {
            if let id = renamingSpaceID { try spaces.update(id) { $0.name = value } }
            else { let space = try spaces.create(name: value, icon: draftIcon); rememberIcon(draftIcon); refresh(); select(.space(space.id)) }
            refresh(); cancelSpaceEditing()
        } catch { self.error = error.localizedDescription }
    }
    private var observations: [StoreObservation] = []
    private var refreshPending = false

    public init(theme: Theme, notes: any NoteStoring, spaces: SpaceStore,
                windows: WindowStateStore, preferences: LibraryPreferencesStore, router: any Routing) {
        self.theme = theme; self.notes = notes; self.spaces = spaces; self.windows = windows
        self.preferences = preferences; self.router = router
        observations = [notes.observe { [weak self] _ in self?.scheduleRefresh() },
                        spaces.observe { [weak self] in self?.scheduleRefresh() },
                        windows.observe { [weak self] in self?.scheduleRefresh() }]
        error = preferences.loadWarning
        refresh()
    }

    private func scheduleRefresh() {
        guard !refreshPending else { return }
        refreshPending = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            refreshPending = false; refresh()
        }
    }

    public func refresh(now: Date = Date(), calendar: Calendar = .current) {
        perform {
            let listing = try notes.list(), trash = try notes.listTrash()
            index = LibraryIndex(notes: listing.notes, trash: trash.notes, windows: windows.all, events: calendarEvents, now: now, calendar: calendar)
            if let upcomingID, !index.upcoming.contains(where: { $0.id == upcomingID }) { dismissUpcoming() }
            spaceList = spaces.spaces
            let failures = listing.failures + trash.failures
            if !failures.isEmpty { error = failures.map { $0.error.description }.joined(separator: "\n") }
        }
    }

    public var readEvents: (DateInterval) -> [CalendarEvent] = { _ in [] }
    public var linkedDestination: (ScheduleItem) -> ScheduleDestination? = { _ in nil }

    func markerDestination(for item: ScheduleItem) -> ScheduleDestination? {
        guard let link = item.link, link.kind == nil || link.kind == item.kind else { return nil }
        return linkedDestination(item)
    }

    public var openCalendarEvent: (CalendarEvent) -> Void = { _ in }
    private var calendarEvents: [CalendarEvent] = []

    public func refreshCalendar(now: Date = Date(), calendar: Calendar = .current) {
        calendarEvents = readEvents(LibraryIndex.upcomingInterval(now: now, calendar: calendar))
        refresh(now: now, calendar: calendar)
    }

    public func opened() {
        refreshCalendar()
        select(validated(settings.opensLastSelection ? settings.lastSelection : settings.visibleViews.first ?? .all))
    }
    private func validated(_ value: LibrarySelection) -> LibrarySelection {
        switch value {
        case .archive: return .archived
        case .space(nil), .day(nil, _): return .all
        case .space(let id), .day(let id, _):
            if let id, spaces.space(for: id) == nil { return .today }
        default: break
        }
        if LibrarySelection.views.contains(value), !settings.visibleViews.contains(value) {
            return settings.visibleViews.first ?? .all
        }
        return value
    }
    public func select(_ value: LibrarySelection) {
        selectedNoteID = nil
        selectedConversation = nil
        let target: LibrarySelection
        switch value {
        case .archive: target = .archived
        case .space(nil): target = .all
        default: target = value
        }
        dismissUpcoming()
        selection = target
        changeSettings { $0.lastSelection = target }
    }
    private(set) var upcomingID: String?
    @ObservationIgnored weak var upcomingSourceView: NSView?
    @ObservationIgnored weak var upcomingDetailView: NSView?

    package func toggleUpcoming(_ id: String) {
        upcomingID = upcomingID == id ? nil : id
    }

    func dismissUpcoming() { upcomingID = nil }

    func newNote(in space: SpaceID?) {
        var draft = NoteDraft()
        draft.spaceID = space
        router.route(.newNote(NewNoteRequest(draft: draft)))
    }

    func newNoteInSelection() {
        switch selection {
        case .space(let id), .day(let id, _): newNote(in: id)
        default: newNote(in: nil)
        }
    }

    var showAllUpcoming = false
    var sections: [LibraryIndex.Section] { index.sections(for: selection) }
    public var showsNewNote: Bool { selection != .conversations && selection != .trash && selection != .archived }
    func toggleArchive(_ note: Note) {
        perform { try notes.update(note.id) { $0.isArchived = !note.isArchived }; refresh() }
    }
    public var rows: [Note] { index.rows(for: selection) }

    /// 한 번 클릭은 선택만 한다. 더블 클릭과 키보드 열기는 구분한다.
    public func activate(_ note: Note, clickCount: Int = 1) {
        selectedNoteID = note.id
        if clickCount >= 2 { open(note) }
    }
    public func openSelected() {
        if selection == .conversations {
            if let selectedConversation { openConversation(selectedConversation) }
            return
        }
        guard let id = selectedNoteID,
              let note = (rows + index.notes).first(where: { $0.id == id }) else { return }
        open(note)
    }
    public func moveSelection(by offset: Int) {
        if selection == .conversations {
            let ids = ConversationDay.sections(conversations(), calendar: index.calendar).flatMap { $0.conversations.map(\.id) }
            guard !ids.isEmpty else { return }
            let position = selectedConversation.flatMap { ids.firstIndex(of: $0) }
            let next = position.map { min(max($0 + offset, 0), ids.count - 1) } ?? (offset < 0 ? ids.count - 1 : 0)
            selectedConversation = ids[next]
            return
        }
        guard !rows.isEmpty else { return }
        let rows = sections.flatMap(\.notes)
        let position = selectedNoteID.flatMap { id in rows.firstIndex { $0.id == id } }
        let next = position.map { min(max($0 + offset, 0), rows.count - 1) } ?? (offset < 0 ? rows.count - 1 : 0)
        selectedNoteID = rows[next].id
    }
    public func reminderPresentation(for note: Note) -> ReminderPresentation? {
        note.displayedSchedule(at: index.now, calendar: index.calendar).map { ReminderPresentation(item: $0, now: index.now, options: displayOptions, calendar: index.calendar) }
    }

    public func open(_ note: Note) {
        if index.trash.contains(where: { $0.id == note.id }) { restore(note.id) }
        else { _ = router.route(.openNote(note.id)) }
    }
    public func restore(_ id: NoteID) {
        perform {
            let restored = try notes.restoreFromTrash(id)
            if let spaceID = restored.spaceID, spaces.space(for: spaceID) == nil {
                try notes.update(id) { $0.spaceID = nil }
            }
            _ = router.route(.openNote(id))
            refresh()
        }
    }
    public func move(_ id: NoteID, to space: SpaceID?) throws {
        if let space, spaces.space(for: space) == nil { throw SpaceStore.MutationError.missingSpace }
        try notes.update(id) { $0.spaceID = space }
        refresh()
    }
    public func createSpace(name: String) {
        perform {
            let space = try spaces.create(name: name)
            expanded.insert(space.id)
            refresh(); select(.space(space.id))
        }
    }
    public func renameSpace(_ id: SpaceID, name: String) {
        perform { try spaces.update(id) { $0.name = name }; refresh() }
    }
    public func deleteSpace(_ id: SpaceID) {
        perform {
            try spaces.delete(id, notes: notes)
            refresh(); select(validated(selection))
        }
    }
    public func setIcon(_ icon: SpaceIcon, for id: SpaceID?) {
        guard let id else { draftIcon = icon; return }
        perform {
            try spaces.update(id) { $0.icon = icon }
            rememberIcon(icon)
            refresh()
        }
    }
    private func rememberIcon(_ icon: SpaceIcon) {
        guard icon != .none else { return }
        changeSettings { settings in
            settings.recentIcons.removeAll { $0 == icon }
            settings.recentIcons.insert(icon, at: 0)
            settings.recentIcons = Array(settings.recentIcons.prefix(28))
        }
    }
    public func changeSettings(_ change: (inout LibraryPreferences) -> Void) {
        perform { try preferences.update(change) }
    }
    func importImage(_ url: URL, for space: SpaceID?) {
        perform {
            let name = try SpaceIconAssets.importFile(url, directory: spaces.imageDirectory,
                                                     maxPixels: Int(theme.component(.iconImportMaxPixels)))
            changeSettings { $0.images.append(name) }
            setIcon(.image(name), for: space)
        }
    }
    func perform(_ work: () throws -> Void) {
        do { try work() } catch { self.error = error.localizedDescription }
    }
    func title(_ selection: LibrarySelection) -> String {
        switch selection {
        case .today: "오늘"
        case .floating: "고정됨"
        case .archived: "보관함"
        case .all: "전체 노트"
        case .reminders: "리마인더 있는 노트"
        case .conversations: "대화"
        case .trash: "휴지통"
        case .space(let id): id.flatMap { spaces.space(for: $0)?.name } ?? "스페이스 없음"
        case .archive(let month): month
        case .day(_, let day): dayLabel(day)
        }
    }
    func dayLabel(_ date: Date) -> String {
        let formatter = DateFormatter(); formatter.calendar = index.calendar
        formatter.timeZone = index.calendar.timeZone; formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = index.calendar.isDate(date, inSameDayAs: index.now) ? "MM-dd '오늘'" : "MM-dd E"
        return formatter.string(from: date)
    }
}
