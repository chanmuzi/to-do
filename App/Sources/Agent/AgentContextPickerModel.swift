import Foundation
import Models
import SwiftUI

package struct AgentContextCatalog {
    let notes: [NoteID: Note]
    let spaces: [SpaceID: Space]
    let orderedSpaces: [Space]
    let orderedNotes: [Note]
    let lastOpened: [NoteID: Date]

    package init(notes: [Note] = [], spaces: [Space] = [], windows: [NoteID: NoteWindowState] = [:]) {
        self.notes = Dictionary(uniqueKeysWithValues: notes.map { ($0.id, $0) })
        self.spaces = Dictionary(uniqueKeysWithValues: spaces.map { ($0.id, $0) })
        orderedSpaces = spaces
        lastOpened = windows.compactMapValues(\.lastOpened)
        let times = lastOpened
        orderedNotes = notes.sorted {
            if $0.isArchived != $1.isArchived { return !$0.isArchived }
            return (times[$0.id] ?? .distantPast) > (times[$1.id] ?? .distantPast)
        }
    }

    func name(_ item: AgentContextItem) -> String { item.name(notes: notes, spaces: spaces) }
}

package struct AgentContextControls {
    package var catalog: () -> AgentContextCatalog = { .init() }
    package var openLibrary: (LibrarySelection) -> Void = { _ in }
    package var datePicker: (@escaping (Date) -> Void, @escaping () -> Void) -> AnyView = { _, _ in AnyView(EmptyView()) }
    package var spaceIcon: (Space, CGFloat) -> AnyView = { _, _ in AnyView(Image(systemName: "folder")) }
    package init() {}
}

@Observable final class AgentContextPickerModel {
    enum Row: Hashable { case header(String), item(AgentContextItem), chooseDay }
    let draft: AgentDraft
    let catalog: AgentContextCatalog
    var query = "" { didSet { if oldValue != query { selection = choices.first } } }
    private(set) var space: SpaceID?
    var choosingDay = false
    var selection: Row?
    private var rootQuery = ""

    init(draft: AgentDraft, catalog: AgentContextCatalog) {
        self.draft = draft
        self.catalog = catalog
        selection = choices.first
    }

    var rows: [Row] {
        let term = query.trimmingCharacters(in: .whitespaces)
        func matches(_ row: Row) -> Bool {
            guard !term.isEmpty else { return true }
            switch row {
            case .item(let item): return catalog.name(item).localizedCaseInsensitiveContains(term)
            case .chooseDay: return "날짜 고르기…".localizedCaseInsensitiveContains(term)
            case .header: return false
            }
        }
        if let space {
            return catalog.orderedNotes.filter { $0.spaceID == space && !$0.isArchived }
                .map { Row.item(.note($0.id)) }.filter(matches)
        }
        let views: [Row] = [.item(.view(.pinned)), .item(.view(.today)), .item(.period(.thisWeek)),
                            .item(.period(.lastSevenDays)), .chooseDay]
        let spaces = catalog.orderedSpaces.map { Row.item(.space($0.id)) }
        if !term.isEmpty {
            return (views + spaces + catalog.orderedNotes.map { .item(.note($0.id)) }).filter(matches)
        }
        let recent = catalog.orderedNotes.lazy.filter { !$0.isArchived && self.catalog.lastOpened[$0.id] != nil }.prefix(8)
        return [.header("보기와 날짜")] + views + [.header("스페이스")] + spaces
            + [.header("최근 노트")] + recent.map { Row.item(.note($0.id)) }
    }

    var choices: [Row] { rows.filter { if case .header = $0 { false } else { true } } }

    func move(_ delta: Int) {
        let list = choices
        guard !list.isEmpty else { return }
        let i = selection.flatMap(list.firstIndex) ?? 0
        selection = list[min(max(i + delta, 0), list.count - 1)]
    }

    func toggle(_ row: Row?) {
        selection = row
        switch row {
        case .item(let item): draft.toggleContext(item)
        case .chooseDay: choosingDay = true
        default: break
        }
    }

    func enter(_ id: SpaceID) {
        rootQuery = query
        space = id
        query = ""
        selection = choices.first
    }

    func back() {
        guard let id = space else { return }
        space = nil
        query = rootQuery
        selection = .item(.space(id))
    }

    func choose(_ date: Date) {
        let item = AgentContextItem.period(.day(.init(date)))
        if !draft.conversation.context.contains(item) { draft.toggleContext(item) }
        choosingDay = false
    }
}
