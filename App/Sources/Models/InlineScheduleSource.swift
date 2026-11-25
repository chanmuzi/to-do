import Foundation
import MarkdownSyntax

/// 제목은 노트 단위, 본문은 블록의 첫 물리 줄과 전체 원문으로 연결한다.
public struct InlineScheduleSource: Hashable, Codable, Sendable {
    public var line: Int?
    public var text: String
    public init(line: Int?, text: String) { self.line = line; self.text = text }
}

/// 줄 번호가 아니라 논리 블록의 앞뒤를 비교한다. ⇧↵로 물리 줄 수만 바뀐 편집도 한 블록 수정이다.
private struct ScheduleBlocks {
    let document: MarkdownDocument
    let roots: [Int]
    let sources: [String]

    init(_ text: String) {
        let doc = MarkdownDocument(text)
        document = doc
        roots = doc.lines.indices.filter { doc.lines[$0].continuationOf == nil }
        sources = roots.map { doc.blockSource(at: $0) }
    }
}

extension Note {
    /// 줄 단위로 저장한 예전 연결은 실제 그 줄의 원문이 일치할 때만 블록 연결로 읽는다.
    mutating func resolveLegacyScheduleLines() {
        guard schedules.contains(where: { !$0.isDeleted && ($0.todo != nil || $0.inlineSource?.line != nil) }),
              body.contains("\\") else { return }
        let document = MarkdownDocument(body)
        for index in schedules.indices where !schedules[index].isDeleted {
            let item = schedules[index]
            guard let row = item.inlineSource?.line ?? item.todo?.line, document.lines.indices.contains(row) else { continue }
            let rows = document.blockLines(at: row)
            guard rows.count > 1 else { continue }
            let old = document.string(in: document.lines[row].range)
            let source = document.blockSource(at: row)
            if let inline = item.inlineSource {
                guard inline.line == row, inline.text == old else { continue }
                schedules[index].inlineSource = InlineScheduleSource(line: rows.lowerBound, text: source)
            } else {
                guard let todo = item.todo, TodoAnchor(line: row, sourceLine: old)?.text == todo.text else { continue }
            }
            if item.todo != nil { schedules[index].todo = TodoAnchor(line: rows.lowerBound, sourceLine: source) }
        }
    }

    package mutating func applyEditorBody(_ text: String, replacing range: NSRange? = nil) -> [ScheduleItem] {
        let previous = schedules
        replaceBody(text, replacing: range)
        var removed: [ScheduleItem] = []
        for index in schedules.indices {
            let item = previous[index]
            guard !item.isDeleted, let line = item.inlineSource?.line, line >= 0,
                  schedules[index].inlineSource?.line == -1 else { continue }
            removed.append(item)
            schedules[index].markDeleted()
        }
        return removed
    }

    /// 같은 본문이 여럿이면 실제 편집 범위 밖에서 살아남은 원본을 따라간다.
    package mutating func replaceBody(_ text: String, replacing range: NSRange?) {
        guard body != text else { return }
        guard let range, schedules.contains(where: { $0.inlineSource?.line != nil || $0.todo != nil }) else { body = text; return }
        let old = body
        let previous = schedules
        schedules = []
        body = text
        schedules = previous
        // 빠른 캡처로 만든 예정은 본문 예정 원문 없이 투두 연결만 가진다.
        // 정확한 편집 범위를 아는 동안만 같은 매핑을 사용하고 저장 형식을 유지한다.
        let todoOnly = previous.indices.filter { previous[$0].inlineSource == nil && previous[$0].todo != nil }
        for index in todoOnly {
            guard let line = previous[index].todo?.locate(in: old) else { continue }
            schedules[index].inlineSource = InlineScheduleSource(line: line, text: MarkdownDocument(old).blockSource(at: line))
        }
        defer { for index in todoOnly { schedules[index].inlineSource = nil } }
        moveInlineSources(from: old, replacing: range)
    }

    mutating func moveInlineSources(from oldBody: String, replacing edit: NSRange? = nil) {
        guard oldBody != body, schedules.contains(where: { $0.inlineSource?.line != nil }) else { return }
        let old = ScheduleBlocks(oldBody)
        let new = ScheduleBlocks(body)
        let before = old.sources, after = new.sources
        var prefix = 0
        while prefix < min(before.count, after.count), before[prefix] == after[prefix] { prefix += 1 }
        var suffix = 0
        while suffix < min(before.count, after.count) - prefix,
              before[before.count - suffix - 1] == after[after.count - suffix - 1] { suffix += 1 }
        let changed = prefix..<(before.count - suffix)
        let indentOnly = before.count == after.count && changed.count > 1 && changed.allSatisfy { i in
            func unindented(_ value: String) -> [Substring] {
                value.split(separator: "\n", omittingEmptySubsequences: false).map { $0.drop(while: { $0 == " " || $0 == "\t" }) }
            }
            return unindented(before[i]) == unindented(after[i])
        }
        for index in schedules.indices {
            guard var source = schedules[index].inlineSource, let row = source.line, row >= 0 else { continue }
            let matches = after.indices.filter { after[$0] == source.text }
            guard let i = old.roots.firstIndex(of: row), before[i] == source.text else {
                // 예정 받기와 undo는 새 원문에 맞는 연결을 본문보다 먼저 복원하기도 한다.
                if new.roots.contains(row), new.document.blockSource(at: row) == source.text { continue }
                if matches.count == 1 {
                    let line = new.roots[matches[0]]
                    source.line = line
                    schedules[index].inlineSource = source
                    if schedules[index].todo != nil { schedules[index].todo = TodoAnchor(line: line, sourceLine: source.text) }
                }
                continue
            }
            let original = old.document.sourceRange(for: old.document.blockLines(at: row))
            var destination: Int?
            var removedByEdit = false
            if let edit {
                let delta = new.document.length - old.document.length
                let start: Int
                if NSMaxRange(original) <= edit.location { start = original.location }
                else if original.location >= NSMaxRange(edit) { start = original.location + delta }
                else { start = -1 }
                if start >= 0, start <= new.document.length {
                    let line = new.document.lineIndex(at: start)
                    if new.document.lines[line].start == start, new.document.blockSource(at: line) == source.text {
                        destination = new.roots.firstIndex(of: line)
                    }
                }
                removedByEdit = edit.length > 0 && edit.length + delta == 0
                    && edit.location <= original.location && NSMaxRange(edit) >= NSMaxRange(original)
            }
            if destination == nil && !removedByEdit {
                if before.filter({ $0 == source.text }).count != 1 && edit == nil {
                    schedules[index].inlineSource = nil
                    schedules[index].todo = nil
                    continue
                }
                if indentOnly { destination = i }
                else if changed.count == 1, after.count - prefix - suffix == 1, i == prefix, !after[i].isEmpty {
                    destination = i
                } else if matches.count == 1 { destination = matches.first }
            }
            guard let destination else {
                source.line = -1
                schedules[index].inlineSource = matches.isEmpty || removedByEdit ? source : nil
                schedules[index].todo = nil
                continue
            }
            let line = new.roots[destination]
            source = InlineScheduleSource(line: line, text: after[destination])
            schedules[index].inlineSource = source
            if schedules[index].todo != nil {
                var anchor = TodoAnchor(line: line, sourceLine: source.text)
                if edit != nil && (matches.count > 1 || schedules[index].todo?.usesRecordedLine == true) { anchor?.usesRecordedLine = true }
                schedules[index].todo = anchor
            }
        }
    }
}
