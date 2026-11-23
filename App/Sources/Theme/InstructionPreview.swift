import MarkdownSyntax
import SwiftUI

/// 두 문서를 각각 파싱하므로 삭제한 줄과 추가한 줄 모두 자기 문서의 서식을 사용한다.
struct InstructionPreview: View {
    let theme: Theme
    private let original: MarkdownDocument
    private let revised: MarkdownDocument
    private struct Row {
        let sign: String
        let index: Int
    }
    private let rows: [Row]

    init(theme: Theme, before: String, after: String) {
        self.theme = theme
        original = MarkdownDocument(before)
        revised = MarkdownDocument(after)
        func lines(_ document: MarkdownDocument) -> [String] {
            guard !document.text.isEmpty else { return [] }
            return document.lines.map { document.string(in: $0.range) }
        }
        let old = lines(original), new = lines(revised)
        let diff = new.difference(from: old)
        var removals = Set<Int>(), insertions = Set<Int>()
        for change in diff {
            switch change {
            case .remove(let i, _, _): removals.insert(i)
            case .insert(let i, _, _): insertions.insert(i)
            }
        }
        var output: [Row] = [], i = 0, j = 0
        while i < old.count || j < new.count {
            if removals.contains(i) { output.append(Row(sign: "-", index: i)); i += 1 }
            else if insertions.contains(j) { output.append(Row(sign: "+", index: j)); j += 1 }
            else { output.append(Row(sign: "", index: j)); i += 1; j += 1 }
        }
        rows = output
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(rows.indices, id: \.self) { i in
                let row = rows[i]
                let document = row.sign == "-" ? original : revised
                let line = document.lines[row.index]
                HStack(spacing: 0) {
                    Text(row.sign).frame(width: theme.component(.proposalGutter))
                    ProposalLineContent(theme: theme, line: line, document: document)
                        .padding(.leading, CGFloat(line.level) * theme.component(.indent))
                    Spacer(minLength: 0)
                }.padding(.trailing, theme.space(.sp3))
                    .frame(minHeight: theme.component(.proposalLineHeight))
                    .background(row.sign == "+" ? theme.color(.diffAdd) : row.sign == "-" ? theme.color(.diffDel) : .clear)
            }
        }.font(theme.font(.body, size: theme.component(.proposalFont)))
    }
}
