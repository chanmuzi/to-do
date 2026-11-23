import Foundation
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
        let beforeLines = request.previousText.components(separatedBy: "\n")
        let nextLines = request.nextText.components(separatedBy: "\n")
        let candidates = note.schedules.filter { !$0.isDeleted }
        let direct = candidates.filter { item in
            guard let source = item.inlineSource else { return false }
            guard let line = request.source.line else { return source.line == nil }
            return source.line == line && beforeLines.indices.contains(line)
                && (source.text == beforeLines[line] || source.text == request.source.text)
        }
        let matches = direct.isEmpty ? candidates.filter { item in
            guard let line = request.source.line else { return false }
            if let source = item.inlineSource, source.line != nil {
                return source.text == request.source.text && nextLines.filter { $0 == source.text }.count == 1
            }
            // 빠른 캡처의 투두도 기존 D-068의 유일한 글자 연결로 찾는다.
            return request.todo != nil && item.todo?.locate(in: request.nextText) == line
        } : direct
        guard matches.count <= 1 else { throw InlineScheduleError.ambiguous }
        let previous = matches.first
        var next = previous ?? request.item
        next.start = request.item.start; next.end = request.item.end; next.isDateOnly = request.item.isDateOnly
        next.inlineSource = request.source; next.todo = request.todo
        if previous == nil { next.title = request.todo?.text ?? request.source.text }
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

    private func restore(_ item: ScheduleItem, in id: NoteID) throws {
        let latest = try notes.load(id).schedules.first { $0.id == item.id }
        var restored = item
        // 삭제가 이미 끝났다면 옛 외부 ID를 되살리지 않는다. 아직 대기 중이면 같은 항목을 살린다.
        restored.link = latest?.link; restored.syncedAt = latest?.syncedAt
        restored.syncBaseline = latest?.syncBaseline; restored.syncError = nil
        restored.modified = Date(); restored.isDeleted = false
        try notes.writeSchedule(restored, in: id)
    }
    private func remove(_ itemID: String, in id: NoteID) throws {
        try notes.removeSchedule(itemID, in: id)
        service.enqueue(id)
    }
}

public enum InlineScheduleError: Error { case ambiguous }
