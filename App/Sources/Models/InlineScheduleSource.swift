import Foundation

/// 제목은 노트 단위, 본문은 줄의 정확한 원문으로 연결한다. 위치는 유일한 글을 찾을 때의 보조 정보다.
public struct InlineScheduleSource: Hashable, Codable, Sendable {
    public var line: Int?
    public var text: String
    public init(line: Int?, text: String) { self.line = line; self.text = text }
}

extension Note {
    /// 사용자의 본문 편집에서만 호출한다. 모호한 연결과 이미 끊긴 연결은 삭제 대상에서 뺀다.
    package mutating func applyEditorBody(_ text: String) -> [ScheduleItem] {
        let previous = schedules
        body = text
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

    /// 한 줄 편집과 줄 삽입은 연결이 따라간다. 여러 줄을 합치거나 같은 글이 중복되면 추측하지 않는다.
    mutating func moveInlineSources(from oldBody: String) {
        guard oldBody != body, schedules.contains(where: { $0.inlineSource?.line != nil }) else { return }
        let old = oldBody.components(separatedBy: "\n")
        let new = body.components(separatedBy: "\n")
        var prefix = 0
        while prefix < min(old.count, new.count), old[prefix] == new[prefix] { prefix += 1 }
        var suffix = 0
        while suffix < min(old.count, new.count) - prefix,
              old[old.count - suffix - 1] == new[new.count - suffix - 1] { suffix += 1 }
        for index in schedules.indices {
            guard var source = schedules[index].inlineSource, let oldIndex = source.line, oldIndex >= 0 else { continue }
            // 되돌리기가 먼저 복원한 연결은 뒤이어 복원되는 본문에서 제자리를 찾는다.
            guard old.indices.contains(oldIndex), old[oldIndex] == source.text else {
                let matches = new.indices.filter { new[$0] == source.text }
                if matches.count == 1, let line = matches.first {
                    source.line = line
                    schedules[index].inlineSource = source
                    if schedules[index].todo != nil { schedules[index].todo = TodoAnchor(line: line, sourceLine: new[line]) }
                }
                continue
            }
            let originals = old.indices.filter { old[$0] == source.text }
            guard originals.count == 1 else {
                schedules[index].inlineSource = nil
                schedules[index].todo = nil
                continue
            }
            let matches = new.indices.filter { new[$0] == source.text }
            let destination: Int?
            if matches.count == 1 { destination = matches.first }
            else if matches.isEmpty, old.count - prefix - suffix == 1, new.count - prefix - suffix == 1,
                    oldIndex == prefix, !new[prefix].isEmpty { destination = prefix }
            else { destination = nil }
            guard let destination else {
                source.line = -1
                schedules[index].inlineSource = matches.isEmpty ? source : nil
                schedules[index].todo = nil
                continue
            }
            source.line = destination; source.text = new[destination]
            schedules[index].inlineSource = source
            if schedules[index].todo != nil {
                schedules[index].todo = TodoAnchor(line: destination, sourceLine: new[destination])
            }
        }
    }
}
