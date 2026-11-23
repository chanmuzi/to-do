import Foundation
import Store

/// 다시 미리볼 때 두 편집이 겹치면 어느 쪽도 자동으로 덮어쓰지 않는다.
func reviewedInstructions(before: String, after: String, current: String) throws -> String {
    if before.utf8.elementsEqual(current.utf8) { return after }
    func lines(_ text: String) -> [String] {
        text.isEmpty ? [] : text.components(separatedBy: "\n")
    }
    let old = lines(before), new = lines(after)
    let prefix = zip(old, new).prefix(while: ==).count
    let suffix = zip(old.dropFirst(prefix).reversed(), new.dropFirst(prefix).reversed()).prefix(while: ==).count
    let removed = Array(old[prefix..<(old.count - suffix)])
    let inserted = new[prefix..<(new.count - suffix)]
    var result = lines(current)
    let start: Int
    if removed.isEmpty && suffix == 0 { start = result.count }
    else {
        let matches = (0...result.count).filter { i in
            guard result.dropFirst(i).starts(with: removed) else { return false }
            if !removed.isEmpty { return true }
            return (prefix == 0 || (i > 0 && result[i - 1] == old[prefix - 1]))
                && (suffix == 0 || (i < result.count && result[i] == old[prefix]))
        }
        guard matches.count == 1, let position = matches.first else { throw AgentStore.InstructionConflict.changed }
        start = position
    }
    result.replaceSubrange(start..<(start + removed.count), with: inserted)
    return result.joined(separator: "\n")
}
