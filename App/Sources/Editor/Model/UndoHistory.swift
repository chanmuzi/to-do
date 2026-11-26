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
    var foldsBefore: FoldState?
    var foldsAfter: FoldState?
    /// 글자를 그대로 친 편집 하나. 이어 친 글자는 한 단계로 묶는다.
    var isTyping = false
    var dateEffect: UUID?
}

/// 편집기의 되돌리기 기록. 텍스트 뷰의 것을 쓰지 않고 직접 든다: 바깥이 원문을 바꿨을 때 적어 둔
/// 위치를 따라 옮길 수 있어야 하기 때문이다(바깥의 변경은 되돌리기에 적지 않는다).
nonisolated struct UndoHistory: Equatable, Sendable {
    /// 남겨 두는 단계 수. 넘으면 가장 오래된 것부터 버린다.
    static let limit = 1_000

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
        pushUndo(record)
    }

    /// 되돌리기 쪽에 한 단계를 올린다. 정한 수를 넘으면 가장 오래된 단계를 버린다.
    mutating func pushUndo(_ record: UndoRecord) {
        undoStack.append(record)
        if undoStack.count > Self.limit { undoStack.removeFirst(undoStack.count - Self.limit) }
    }

    /// 바깥의 변경과 사용자의 편집이 같은 자리에서 만났을 때 바깥의 글이 놓이는 쪽.
    private enum Side { case before, after }

    /// 바깥이 지금 원문(길이 `documentLength`)의 `range`를 길이가 `delta`만큼 다른 글로 바꾼다. 적어 둔
    /// 위치를 따라 옮긴다. 바깥의 변경이 사용자가 고친 자리(넣은 글, 지운 자리)에 겹치는 단계는 옮길 수
    /// 없으므로, 그 단계와 그보다 오래된 단계(다시 하기 쪽은 그 뒤의 단계)를 버린다.
    ///
    /// 같은 자리에서 만나는 경우: 바깥이 글을 끼워 넣기만 했고(길이 0인 범위) 그 자리가 사용자가 글을 지운
    /// 자리(되돌리면 글이 되살아나는 곳. 다시 하기 쪽은 글을 다시 넣을 곳)와 꼭 같으면, 되살아날 글이 바깥의
    /// 글 앞에 올지 뒤에 올지 위치만으로는 정해지지 않는다. 뜻이 분명한 두 경우만 옮기고 나머지는 버린다.
    /// - 문서의 끝(빈 문서 포함): 바깥의 글은 덧붙인 것이다. 되살아날 글의 뒤에 둔다.
    /// - 문서의 맨 앞: 바깥의 글은 앞에 붙인 것이다. 되살아날 글의 앞에 둔다.
    /// - 문서의 가운데: 어느 쪽에 두어도 되살린 글이 바깥이 쓴 줄에 붙을 수 있다. 그 단계와 그보다 오래된
    ///   단계(다시 하기 쪽은 그 뒤의 단계)를 버린다.
    /// - Returns: 버린 단계가 있으면 `true`.
    @discardableResult
    /// - Parameter leadsDocument: 바깥의 글이 문서 맨 앞에 붙인 것임을 안다(조합하던 글자 앞에 미뤄 둔 변경).
    ///   그 글자가 지워져 빈 문서가 됐어도 끝이 아니라 맨 앞으로 다룬다.
    mutating func shift(outside range: NSRange, delta: Int, documentLength: Int, leadsDocument: Bool = false) -> Bool {
        // 끼워 넣기가 문서의 끝이나 맨 앞이면, 편집을 거슬러 가도 그 좌표의 끝과 맨 앞에 그대로 있다.
        let tie: Side? = range.length > 0 ? nil
            : range.location == 0 && leadsDocument ? .before
            : range.location == documentLength ? .after
            : range.location == 0 ? .before : nil
        let isInsertion = range.length == 0

        // 되돌리기 쪽: 가장 최근 단계부터 거슬러 올라간다. 바깥의 범위를 각 편집 전의 좌표로 옮겨 간다.
        var records = undoStack + (open.map { [$0] } ?? [])
        var outside = range
        var kept = records.count
        var index = records.count - 1
        // 열린 단계가 고친 원문 앞의 좌표로 옮긴 바깥의 범위. 다시 하기 기록은 그 좌표에 적혀 있다.
        var outsideBeforeOpen: NSRange? = open == nil ? range : nil
        undo: while index >= 0 {
            records[index].selectionAfter = Self.moved(records[index].selectionAfter, outside: outside, delta: delta, pushesStart: tie == .before)
            var edit = records[index].edits.count - 1
            while edit >= 0 {
                let current = records[index].edits[edit]
                let side: Side
                if isInsertion, current.newLength == 0, current.location == outside.location {
                    guard let tie else { break undo }
                    side = tie
                } else if NSMaxRange(outside) <= current.location {
                    side = .before
                } else if outside.location >= current.location + current.newLength {
                    side = .after
                } else {
                    break undo
                }
                switch side {
                case .before: records[index].edits[edit].location += delta
                case .after: outside.location -= current.newLength - current.oldLength
                }
                edit -= 1
            }
            records[index].selectionBefore = Self.moved(records[index].selectionBefore, outside: outside, delta: delta, pushesStart: tie == .before)
            if outsideBeforeOpen == nil { outsideBeforeOpen = outside }
            kept = index
            index -= 1
        }
        let survivors = Array(records[kept...])
        var dropped = kept > 0
        if open != nil {
            open = survivors.last
            undoStack = Array(survivors.dropLast())
        } else {
            undoStack = survivors
        }

        // 다시 하기 쪽: 다음에 다시 할 단계(맨 뒤)부터. 바깥의 범위를 각 편집 뒤의 좌표로 옮겨 간다.
        // 열린 단계를 버렸으면 그 편집은 되돌릴 수 없는 글이 됐다. 그 앞의 원문에 적힌 다시 하기 기록은 쓸 수 없다.
        guard let start = outsideBeforeOpen else {
            dropped = dropped || !redoStack.isEmpty
            redoStack = []
            return dropped
        }
        outside = start
        var keptRedo: [UndoRecord] = []
        redo: for var record in redoStack.reversed() {
            record.selectionBefore = Self.moved(record.selectionBefore, outside: outside, delta: delta, pushesStart: tie == .before)
            for edit in record.edits.indices {
                let current = record.edits[edit]
                let side: Side
                if isInsertion, current.oldLength == 0, current.location == outside.location {
                    guard let tie else { break redo }
                    side = tie
                } else if NSMaxRange(outside) <= current.location {
                    side = .before
                } else if outside.location >= current.location + current.oldLength {
                    side = .after
                } else {
                    break redo
                }
                switch side {
                case .before: record.edits[edit].location += delta
                case .after: outside.location += current.newLength - current.oldLength
                }
            }
            record.selectionAfter = Self.moved(record.selectionAfter, outside: outside, delta: delta, pushesStart: tie == .before)
            keptRedo.append(record)
        }
        dropped = dropped || keptRedo.count < redoStack.count
        redoStack = keptRedo.reversed()
        return dropped
    }

    /// 그 단계를 지금 원문에 그대로 되돌릴(다시 할) 수 있는지: 편집마다 적어 둔 글이 그 자리에 그대로 있다.
    /// 하나라도 다르면 기록이 원문과 어긋난 것이므로 그 단계를 쓰면 안 된다.
    static func matches(_ record: UndoRecord, in text: String, redo: Bool) -> Bool {
        var current = text as NSString
        for edit in redo ? record.edits : record.edits.reversed() {
            let expected = redo ? edit.old : edit.new
            let range = NSRange(location: edit.location, length: expected.utf16.count)
            guard range.location >= 0, NSMaxRange(range) <= current.length, current.substring(with: range) == expected else { return false }
            if record.edits.count > 1 {
                current = current.replacingCharacters(in: range, with: redo ? edit.new : edit.old) as NSString
            }
        }
        return true
    }

    /// - Parameter pushesStart: 바깥의 글이 그 자리에 있던 것의 앞에 놓인다(문서 맨 앞에 붙인 글). 그 자리의
    ///   선택도 바깥의 글 뒤로 간다.
    private static func moved(_ selection: NSRange, outside: NSRange, delta: Int, pushesStart: Bool) -> NSRange {
        func move(_ position: Int) -> Int {
            if position < outside.location || (position == outside.location && !pushesStart) { return position }
            if position >= NSMaxRange(outside) { return position + delta }
            return outside.location
        }
        let start = move(selection.location)
        return NSRange(location: start, length: max(0, move(NSMaxRange(selection)) - start))
    }
}
