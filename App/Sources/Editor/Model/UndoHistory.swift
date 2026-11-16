import Foundation

/// 되돌리기에 적는 바꿔 쓰기 하나. 적용한 뒤의 원문에서 `location`부터 `new`가 놓여 있다.
nonisolated struct UndoEdit: Equatable, Sendable {
    var location: Int
    var old: String
    var new: String

    var oldLength: Int { old.utf16.count }
    var newLength: Int { new.utf16.count }
}

/// 되돌리기 한 단계. 사용자의 편집 하나(또는 한 묶음)다.
nonisolated struct UndoRecord: Equatable, Sendable {
    /// 적용한 차례대로. 각 편집의 위치는 그 앞의 편집들이 적용된 원문 기준이다.
    var edits: [UndoEdit] = []
    var selectionBefore: NSRange
    var selectionAfter: NSRange
    /// 되돌릴 때(다시 할 때) 되살릴 접힘. 줄 번호를 따라 옮기는 것으로 충분하면 `nil`.
    var foldsBefore: Set<Int>?
    var foldsAfter: Set<Int>?
    /// 글자를 그대로 친 편집 하나. 이어 친 글자는 한 단계로 묶는다.
    var isTyping = false
}

/// 편집기의 되돌리기 기록. 텍스트 뷰의 것을 쓰지 않고 직접 든다: 바깥이 원문을 바꿨을 때 적어 둔
/// 위치를 따라 옮길 수 있어야 하기 때문이다(바깥의 변경은 되돌리기에 적지 않는다).
nonisolated struct UndoHistory: Equatable, Sendable {
    var undoStack: [UndoRecord] = []
    var redoStack: [UndoRecord] = []
    /// 아직 닫지 않은 단계(편집이 이어지는 중).
    var open: UndoRecord?

    var canUndo: Bool { !undoStack.isEmpty || !(open?.edits.isEmpty ?? true) }
    var canRedo: Bool { !redoStack.isEmpty && (open?.edits.isEmpty ?? true) }

    /// 열린 단계를 닫아 기록에 올린다. 새 편집이 올라가면 다시 하기 기록은 사라진다.
    /// - Parameter coalescesTyping: 바로 앞 단계가 이어 친 글자이고 이 단계가 그 뒤에 붙으면 하나로 합친다.
    mutating func close(selectionAfter: NSRange, coalescesTyping: Bool) {
        guard var record = open else { return }
        open = nil
        guard !record.edits.isEmpty else { return }
        record.selectionAfter = selectionAfter
        redoStack = []
        if coalescesTyping, record.isTyping, let last = undoStack.last, last.isTyping,
           let previous = last.edits.last, let edit = record.edits.first,
           edit.location == previous.location + previous.newLength, last.selectionAfter == record.selectionBefore,
           !edit.new.hasPrefix(" ") || previous.new.hasSuffix(" ") {
            undoStack[undoStack.count - 1].edits[last.edits.count - 1].new += edit.new
            undoStack[undoStack.count - 1].selectionAfter = selectionAfter
            return
        }
        undoStack.append(record)
    }

    /// 바깥이 지금 원문의 `range`를 길이가 `delta`만큼 다른 글로 바꾼다. 적어 둔 위치를 따라 옮긴다.
    /// 바깥의 변경이 사용자가 고친 자리(넣은 글, 지운 자리)에 겹치는 단계는 옮길 수 없으므로,
    /// 그 단계와 그보다 오래된 단계(다시 하기 쪽은 그 뒤의 단계)를 버린다.
    mutating func shift(outside range: NSRange, delta: Int) {
        // 되돌리기 쪽: 가장 최근 단계부터 거슬러 올라간다. 바깥의 범위를 각 편집 전의 좌표로 옮겨 간다.
        var records = undoStack + (open.map { [$0] } ?? [])
        var outside = range
        var kept = records.count
        var index = records.count - 1
        undo: while index >= 0 {
            records[index].selectionAfter = Self.moved(records[index].selectionAfter, outside: outside, delta: delta)
            var edit = records[index].edits.count - 1
            while edit >= 0 {
                let current = records[index].edits[edit]
                if NSMaxRange(outside) <= current.location {
                    records[index].edits[edit].location += delta
                } else if outside.location >= current.location + current.newLength {
                    outside.location -= current.newLength - current.oldLength
                } else {
                    break undo
                }
                edit -= 1
            }
            records[index].selectionBefore = Self.moved(records[index].selectionBefore, outside: outside, delta: delta)
            kept = index
            index -= 1
        }
        let survivors = Array(records[kept...])
        if open != nil {
            open = survivors.last
            undoStack = Array(survivors.dropLast())
        } else {
            undoStack = survivors
        }

        // 다시 하기 쪽: 다음에 다시 할 단계(맨 뒤)부터. 바깥의 범위를 각 편집 뒤의 좌표로 옮겨 간다.
        outside = range
        var keptRedo: [UndoRecord] = []
        redo: for var record in redoStack.reversed() {
            record.selectionBefore = Self.moved(record.selectionBefore, outside: outside, delta: delta)
            for edit in record.edits.indices {
                let current = record.edits[edit]
                if NSMaxRange(outside) <= current.location {
                    record.edits[edit].location += delta
                } else if outside.location >= current.location + current.oldLength {
                    outside.location += current.newLength - current.oldLength
                } else {
                    break redo
                }
            }
            record.selectionAfter = Self.moved(record.selectionAfter, outside: outside, delta: delta)
            keptRedo.append(record)
        }
        redoStack = keptRedo.reversed()
    }

    private static func moved(_ selection: NSRange, outside: NSRange, delta: Int) -> NSRange {
        func move(_ position: Int) -> Int {
            if position <= outside.location { return position }
            if position >= NSMaxRange(outside) { return position + delta }
            return outside.location
        }
        let start = move(selection.location)
        return NSRange(location: start, length: max(0, move(NSMaxRange(selection)) - start))
    }
}
