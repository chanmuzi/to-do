import Foundation
import Models

/// 한 줄에 표시할 제목, 검색 문맥과 핀 상태.
nonisolated struct BrowseNoteRow: Hashable, Sendable {
    let id: NoteID
    let spaceID: SpaceID?
    /// 비어 있으면 "제목 없음"으로 보인다.
    let title: String
    let preview: String
    /// `preview`에서 굵게 보일 자리(글자 차례). 본문에서 맞았을 때만 있다.
    let previewHighlight: Range<Int>?
    let titleHighlight: Range<Int>?
    let isFloating: Bool
}

/// 목록에 놓이는 것 하나.
nonisolated enum BrowseEntry: Hashable, Sendable {
    /// 검색 전 최근 구획 이름.
    case header(String)
    case note(BrowseNoteRow)
    /// "“검색어” 새 노트 만들기".
    case create(query: String)
    case separator
    /// "라이브러리 열기".
    case library

    /// ↑↓로 고르고 ↵로 열 수 있는 줄인지.
    var isSelectable: Bool {
        switch self {
        case .note, .create, .library: true
        case .header, .separator: false
        }
    }
}

/// 찾기 전에 한 번 풀어 둔 노트. 글자를 칠 때마다 본문을 다시 풀지 않는다.
nonisolated struct BrowseIndexedNote: Sendable {
    let note: Note
    let flattenedBody: String
    let title: BrowseSearchText
    let body: BrowseSearchText

    init(_ note: Note) {
        self.note = note
        flattenedBody = BrowsePreview.flatten(note.body)
        title = BrowseSearchText(note.title.trimmingCharacters(in: .whitespacesAndNewlines))
        body = BrowseSearchText(flattenedBody)
    }
}

/// 목록의 내용과 차례(spec 8).
nonisolated struct BrowseContent: Hashable, Sendable {
    static let recentTitle = "최근"
    /// 최근 목록과 검색 결과 창에 보이는 최대 노트 수.
    static let recentLimit = 8

    let entries: [BrowseEntry]

    /// - Parameters:
    ///   - notes: 최근에 고친 것이 앞인 노트 목록(`NoteStoring.list()`의 차례).
    ///   - floating: 열려 있고 항상 위에 고정된 노트.
    ///   - lastOpened: 노트마다 마지막으로 포커스를 받은 시각.
    ///   - excluding: 목록에서 뺄 노트(노트 찾기를 연 그 노트).
    ///   - showsLibrary: 맨 아래에 "라이브러리 열기"를 둘지. 그 요청을 받는 화면이 이어져 있지 않으면 두지 않는다
    ///     (눌러도 아무 일이 없는 줄을 내놓지 않는다). 그때는 그 위의 구분선도 없다.
    init(
        notes: [BrowseIndexedNote], floating: [NoteID], lastOpened: [NoteID: Date] = [:], query: BrowseQuery,
        excluding current: NoteID?, showsLibrary: Bool = true
    ) {
        let candidates = BrowseRecency.sorted(notes.filter { $0.note.id != current }, openedTimes: lastOpened)
        let pins = Set(floating)
        var entries: [BrowseEntry]
        if query.isEmpty {
            let recent = candidates.filter { !$0.note.isArchived && lastOpened[$0.note.id] != nil }.prefix(Self.recentLimit)
            entries = recent.isEmpty ? [] : [.header(Self.recentTitle)]
            entries += recent.map { Self.row($0, pins: pins) }
        } else {
            var titles: [BrowseEntry] = [], bodies: [BrowseEntry] = []
            var archivedTitles: [BrowseEntry] = [], archivedBodies: [BrowseEntry] = []
            for note in candidates {
                if let match = BrowseMatcher.firstMatch(of: query, in: note.title) {
                    let entry = Self.row(note, pins: pins, titleMatch: match)
                    if note.note.isArchived { archivedTitles.append(entry) } else { titles.append(entry) }
                } else if let match = BrowseMatcher.firstMatch(of: query, in: note.body) {
                    let entry = Self.row(note, pins: pins, bodyMatch: match)
                    if note.note.isArchived { archivedBodies.append(entry) } else { bodies.append(entry) }
                }
            }
            entries = titles + bodies + archivedTitles + archivedBodies + [.create(query: query.text)]
        }
        if showsLibrary {
            if !entries.isEmpty { entries.append(.separator) }
            entries.append(.library)
        }
        self.entries = entries
    }

    private static func row(_ indexed: BrowseIndexedNote, pins: Set<NoteID>,
                            titleMatch: Range<Int>? = nil, bodyMatch: Range<Int>? = nil) -> BrowseEntry {
        let preview = BrowsePreview.display(indexed.flattenedBody, match: bodyMatch)
        return .note(BrowseNoteRow(
            id: indexed.note.id, spaceID: indexed.note.spaceID,
            title: indexed.note.title.trimmingCharacters(in: .whitespacesAndNewlines),
            preview: preview.text, previewHighlight: preview.highlight, titleHighlight: titleMatch,
            isFloating: pins.contains(indexed.note.id)
        ))
    }
}
