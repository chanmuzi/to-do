import Foundation

/// 하위 계층의 부모 관계(D-043). 들여 쓴 줄은 바로 위 단계의 부모 항목(목록, 투두, 토글, 인용문) 아래에만
/// 놓인다. 부모가 없는 들여쓰기(다른 프로그램이 쓴 파일)는 그대로 읽는다.
///
/// 부모를 찾을 때 빈 줄(글자 없는 본문 줄)은 건너뛴다: "바로 앞의 비지 않은 줄"이 기준이다.
nonisolated enum ListStructure {
    /// 앞에서부터 줄을 읽어 가며 단계마다 부모 항목이 있는지 들고 있는 것.
    struct Context {
        /// `parents[k]`: 지금 자리에서 단계 `k`의 가장 가까운 줄이 부모 항목인지.
        private var parents = [Bool](repeating: false, count: MarkdownDocument.maxLevel + 2)

        /// 지금 자리에서 단계 `level`의 부모 항목이 있는지(단계 `level + 1`의 줄이 그 아래에 놓일 수 있는지).
        func hasParent(atLevel level: Int) -> Bool {
            parents.indices.contains(level) && parents[level]
        }

        /// 줄 하나를 읽는다. 빈 줄은 건너뛴다.
        mutating func add(_ line: MarkdownLine, level: Int? = nil) {
            guard line.continuationOf == nil, !ListStructure.isBlank(line) else { return }
            let level = min(level ?? line.level, parents.count - 1)
            parents[level] = line.kind.isParentItem
            for deeper in (level + 1)..<parents.count { parents[deeper] = false }
        }
    }

    /// 글자가 없는 본문 줄.
    static func isBlank(_ line: MarkdownLine) -> Bool {
        line.isBlankParagraph
    }

    /// 줄마다 부모가 있는지(0단계 줄은 언제나 있다).
    static func hasParent(in doc: MarkdownDocument) -> [Bool] {
        var context = Context()
        return doc.lines.map { line in
            let result = line.level == 0 || context.hasParent(atLevel: line.level - 1)
            context.add(line)
            return result
        }
    }

    /// 그 줄이 하위 줄을 가진 부모 항목인지: 그 줄보다 얕거나 같은 단계의 줄이 나오기 전에 바로 아래 단계의
    /// 줄이 있다(빈 줄은 건너뛴다). 문서 전체를 읽지 않고 그 줄 뒤만 본다.
    static func hasChildren(_ doc: MarkdownDocument, _ index: Int) -> Bool {
        let parent = doc.lines[index]
        guard parent.kind.isParentItem else { return false }
        for line in doc.lines[(index + 1)...] where line.continuationOf == nil && !isBlank(line) {
            if line.level <= parent.level { return false }
            if line.level == parent.level + 1 { return true }
        }
        return false
    }

    /// 그 줄 앞까지 읽은 것.
    static func context(before index: Int, in doc: MarkdownDocument) -> Context {
        var context = Context()
        for line in doc.lines[0..<index] { context.add(line) }
        return context
    }
}
