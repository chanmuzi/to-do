import Foundation

/// 제목은 노트 단위, 본문은 줄의 정확한 원문으로 연결한다. 위치는 유일한 글을 찾을 때의 보조 정보다.
public struct InlineScheduleSource: Hashable, Codable, Sendable {
    public var line: Int?
    public var text: String
    public init(line: Int?, text: String) { self.line = line; self.text = text }
}

extension Note {
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
            guard var source = schedules[index].inlineSource, let oldIndex = source.line,
                  old.indices.contains(oldIndex), old[oldIndex] == source.text else { continue }
            let originals = old.indices.filter { old[$0] == source.text }
            guard originals.count == 1, let original = originals.first else { continue }
            let matches = new.indices.filter { new[$0] == source.text }
            let destination: Int?
            if matches.count == 1 { destination = matches.first }
            else if matches.isEmpty, old.count - prefix - suffix == 1, new.count - prefix - suffix == 1,
                    original == prefix { destination = prefix }
            else { destination = nil }
            guard let destination else { source.line = -1; schedules[index].inlineSource = source; continue }
            source.line = destination; source.text = new[destination]
            schedules[index].inlineSource = source
            if schedules[index].todo != nil {
                schedules[index].todo = TodoAnchor(line: destination, sourceLine: new[destination])
            }
        }
    }
}
