import Foundation
import Models

/// 노트 한 줄(spec 8): 스페이스 아이콘 / 제목 / 본문 첫머리 / 리마인더 / 떠 있으면 핀.
nonisolated struct BrowseNoteRow: Hashable, Sendable {
    let id: NoteID
    let spaceID: SpaceID?
    /// 비어 있으면 "제목 없음"으로 보인다.
    let title: String
    let preview: String
    /// `preview`에서 굵게 보일 자리(글자 차례). 본문에서 맞았을 때만 있다.
    let previewHighlight: Range<Int>?
    let reminder: Date?
    let colorID: PaletteID?
    let isFloating: Bool
}

/// 목록에 놓이는 것 하나.
nonisolated enum BrowseEntry: Hashable, Sendable {
    /// 구획 이름("떠 있는 노트", "최근에 연 노트").
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
        title = BrowseSearchText(note.title)
        body = BrowseSearchText(flattenedBody)
    }
}

/// 목록의 내용과 차례(spec 8).
nonisolated struct BrowseContent: Hashable, Sendable {
    static let floatingTitle = "떠 있는 노트"
    static let recentTitle = "최근에 연 노트"
    /// 최근에 연 노트는 여덟 줄까지만 보인다(spec 16, 가정). 나머지는 찾아서 간다.
    static let recentLimit = 8

    let entries: [BrowseEntry]

    /// - Parameters:
    ///   - notes: 최근에 고친 것이 앞인 노트 목록(`NoteStoring.list()`의 차례).
    ///   - floating: 떠 있는 노트. 앞에 있는 창이 먼저.
    ///   - lastOpened: 노트마다 마지막으로 연 때. "최근에 연 노트"의 차례를 정하고, 없는 노트는 고친 시각을 쓴다.
    ///   - excluding: 목록에서 뺄 노트(노트 찾기를 연 그 노트).
    ///   - showsLibrary: 맨 아래에 "라이브러리 열기"를 둘지. 그 요청을 받는 화면이 이어져 있지 않으면 두지 않는다
    ///     (눌러도 아무 일이 없는 줄을 내놓지 않는다). 그때는 그 위의 구분선도 없다.
    init(
        notes: [BrowseIndexedNote], floating: [NoteID], lastOpened: [NoteID: Date] = [:], query: BrowseQuery,
        excluding current: NoteID?, showsLibrary: Bool = true
    ) {
        let candidates = notes.filter { $0.note.id != current }
        let floatingSet = Set(floating)
        var entries = query.isEmpty
            ? Self.sections(candidates, floating: floating, lastOpened: lastOpened)
            : Self.results(candidates, floating: floatingSet, query: query)
        if showsLibrary {
            if !entries.isEmpty { entries.append(.separator) }
            entries.append(.library)
        }
        self.entries = entries
    }

    /// 글자를 치기 전: "떠 있는 노트" 다음 "최근에 연 노트". 빈 구획은 이름도 보이지 않는다.
    private static func sections(
        _ notes: [BrowseIndexedNote], floating: [NoteID], lastOpened: [NoteID: Date]
    ) -> [BrowseEntry] {
        let byID = Dictionary(notes.map { ($0.note.id, $0) }, uniquingKeysWith: { first, _ in first })
        let floatingRows = floating.compactMap { byID[$0] }.map { row($0, isFloating: true, match: nil) }
        let floatingSet = Set(floating)
        let recentRows = BrowseRecency
            .sorted(notes.filter { !floatingSet.contains($0.note.id) }, openedTimes: lastOpened)
            .prefix(recentLimit)
            .map { row($0, isFloating: false, match: nil) }

        var entries: [BrowseEntry] = []
        if !floatingRows.isEmpty { entries += [.header(floatingTitle)] + floatingRows.map(BrowseEntry.note) }
        if !recentRows.isEmpty { entries += [.header(recentTitle)] + recentRows.map(BrowseEntry.note) }
        return entries
    }

    /// 찾는 중: 구획 이름 없이 제목에서 맞은 것 다음에 본문에서만 맞은 것. 맨 아래에 새 노트 만들기.
    private static func results(
        _ notes: [BrowseIndexedNote], floating: Set<NoteID>, query: BrowseQuery
    ) -> [BrowseEntry] {
        var titleMatches: [BrowseEntry] = []
        var bodyMatches: [BrowseEntry] = []
        for indexed in notes {
            let inBody = BrowseMatcher.firstMatch(of: query, in: indexed.body)
            let inTitle = BrowseMatcher.firstMatch(of: query, in: indexed.title) != nil
            guard inTitle || inBody != nil else { continue }
            let entry = BrowseEntry.note(row(indexed, isFloating: floating.contains(indexed.note.id), match: inBody))
            if inTitle { titleMatches.append(entry) } else { bodyMatches.append(entry) }
        }
        return titleMatches + bodyMatches + [.create(query: query.text)]
    }

    private static func row(_ indexed: BrowseIndexedNote, isFloating: Bool, match: Range<Int>?) -> BrowseNoteRow {
        let preview = BrowsePreview.display(indexed.flattenedBody, match: match)
        return BrowseNoteRow(
            id: indexed.note.id,
            spaceID: indexed.note.spaceID,
            title: indexed.note.title.trimmingCharacters(in: .whitespacesAndNewlines),
            preview: preview.text,
            previewHighlight: preview.highlight,
            reminder: indexed.note.reminder,
            colorID: indexed.note.colorID,
            isFloating: isFloating
        )
    }
}
