import Foundation
import MarkdownSyntax
import DateTime
import Models
import Store

/// 글의 undo 단계와 함께 쓰는 항목 단위 변경. 외부 연결은 최신 값을 유지한다.
@MainActor public final class InlineScheduleWriter {
    private let notes: any NoteStoring
    private let service: ScheduleService
    public init(notes: any NoteStoring, service: ScheduleService) { self.notes = notes; self.service = service }

    public func accept(_ request: InlineDateAcceptance, in id: NoteID) throws -> InlineDateEffect {
        let note = try notes.load(id)
        let before = MarkdownDocument(request.previousText)
        let nextDocument = MarkdownDocument(request.nextText)
        let candidates = note.schedules.filter { !$0.isDeleted }
        let direct = candidates.filter { item in
            guard let source = item.inlineSource else { return false }
            guard let line = request.source.line else { return source.line == nil }
            return source.line == line && before.lines.indices.contains(line)
                && (source.text == before.blockSource(at: line) || source.text == request.source.text)
        }
        let matches = direct.isEmpty ? candidates.filter { item in
            guard let line = request.source.line else { return false }
            if let source = item.inlineSource, source.line != nil {
                return source.text == request.source.text && nextDocument.lines.indices.filter { nextDocument.lines[$0].continuationOf == nil && nextDocument.blockSource(at: $0) == source.text }.count == 1
            }
            // 빠른 캡처의 투두도 기존 D-068의 유일한 글자 연결로 찾는다.
            return request.todo != nil && item.todo?.locate(in: request.nextText) == line
        } : direct
        guard matches.count <= 1 else { throw InlineScheduleError.ambiguous }
        let previous = matches.first
        var next = previous ?? request.item
        next.start = request.item.start; next.end = request.item.end; next.isDateOnly = request.item.isDateOnly
        next.inlineSource = request.source; next.todo = request.todo
        if previous == nil { next.title = NotePreviewText.removingHardBreakMarkers(in: request.todo?.text ?? request.source.text) }
        if let todo = request.todo { next.isCompleted = todo.completed(in: request.nextText) ?? false }
        next.modified = Date(); next.isDeleted = false
        try notes.writeSchedule(next, in: id)
        service.register(id, itemID: next.id, requestPermission: true)
        let accepted = next
        return InlineDateEffect(undo: { [self] in
            if let previous { try restore(previous, in: id) }
            else { try remove(accepted.id, in: id) }
        }, redo: { [self] in
            try restore(accepted, in: id)
            // 다시 하기는 기존 권한을 쓰며 새 권한 창을 띄우지 않는다.
            service.register(id, itemID: accepted.id, requestPermission: false)
        })
    }

    /// 본문과 삭제 대기를 한 변경으로 저장한다. 동기화는 이미 허용된 권한만 사용한다.
    public func removeMissingSources(from previous: String, to text: String, in id: NoteID, replacing range: NSRange? = nil) throws
        -> (items: [ScheduleItem], effect: InlineDateEffect)? {
        var removed: [ScheduleItem] = []
        try notes.scheduleUpdate(id) { note in
            guard note.body == previous else { return }
            removed = note.applyEditorBody(text, replacing: range)
        }
        guard !removed.isEmpty else { return nil }
        service.enqueue(id)
        let items = removed
        let effect = InlineDateEffect(undo: { [self] in
            try notes.scheduleUpdate(id) { note in
                for item in items {
                    let index = note.schedules.firstIndex { $0.id == item.id }
                    let restored = restoredItem(item, latest: index.map { note.schedules[$0] })
                    if let index { note.schedules[index] = restored }
                    else { note.schedules.append(restored) }
                }
            }
            for item in items { service.register(id, itemID: item.id, requestPermission: false) }
        }, redo: { [self] in
            let ids = Set(items.map(\.id))
            try notes.scheduleUpdate(id) { note in
                for index in note.schedules.indices where ids.contains(note.schedules[index].id) {
                    note.schedules[index].markDeleted()
                }
            }
            service.enqueue(id)
        })
        return (items, effect)
    }

    private func restore(_ item: ScheduleItem, in id: NoteID) throws {
        let latest = try notes.load(id).schedules.first { $0.id == item.id }
        try notes.writeSchedule(restoredItem(item, latest: latest), in: id)
    }

    private func restoredItem(_ item: ScheduleItem, latest: ScheduleItem?) -> ScheduleItem {
        var restored = item
        // 삭제가 이미 끝났다면 옛 외부 ID를 되살리지 않는다. 아직 대기 중이면 같은 항목을 살린다.
        restored.link = latest?.link; restored.syncedAt = latest?.syncedAt
        restored.syncBaseline = latest?.syncBaseline; restored.syncError = nil
        restored.modified = Date(); restored.isDeleted = false
        return restored
    }
    private func remove(_ itemID: String, in id: NoteID) throws {
        try notes.removeSchedule(itemID, in: id)
        service.enqueue(id)
    }
}

public enum InlineScheduleError: Error { case ambiguous }
