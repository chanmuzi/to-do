import Models
import SwiftUI

package extension AgentProposal.Status {
    var label: String {
        switch self { case .pending: "받지 않음"; case .accepted: "받음"; case .undone: "되돌림"; case .discarded: "버림" }
    }
}

package extension View {
    func proposalBackground(_ theme: Theme, pending: Bool, radius: CGFloat) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius)
        return self.background {
            if pending {
                shape.fill(LinearGradient(colors: [theme.color(.agentBgA), theme.color(.agentBgM), theme.color(.agentBgB)],
                                          startPoint: .topLeading, endPoint: .bottomTrailing))
                shape.strokeBorder(theme.color(.agentEdgeA), style: StrokeStyle(lineWidth: theme.shape(.borderWidth),
                                                                               dash: [theme.space(.sp1)]))
            } else { shape.fill(theme.color(.surface2)) }
        }
    }
}

/// 카드와 라이브러리에서 같은 노트 변환을 미리 본다.
package struct TodoProposalView: View {
    package let theme: Theme
    package let proposal: AgentProposal
    package let note: Note?
    package let full: Bool
    package let review: () -> Void
    package let conversation: (() -> Void)?
    package let accept: () -> Void
    package let discard: () -> Void

    package init(theme: Theme, proposal: AgentProposal, note: Note?, full: Bool, review: @escaping () -> Void,
                 conversation: (() -> Void)? = nil, accept: @escaping () -> Void, discard: @escaping () -> Void) {
        self.theme = theme; self.proposal = proposal; self.note = note; self.full = full
        self.review = review; self.conversation = conversation; self.accept = accept; self.discard = discard
    }

    private var pending: Bool { proposal.status == .pending }
    private var preview: [(String, Bool)] {
        guard let note else { return [] }
        let body = pending ? proposal.lines.reduce(note.body) { TodoAppender.append($1, to: $0) } : note.body
        var rows = body.components(separatedBy: .newlines)
        if body.contains("\r\n") { rows = body.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n") }
        if rows.last == "" { rows.removeLast() }
        let firstAdded = pending ? rows.count - proposal.lines.count : rows.count
        return rows.enumerated().compactMap { index, text in
            full || index >= firstAdded ? (text, index >= firstAdded) : nil
        }
    }

    package var body: some View {
        VStack(alignment: .leading, spacing: theme.space(.sp2)) {
            HStack(spacing: theme.component(.agentChipInset)) {
                AgentFace(theme: theme, state: .done)
                Text(proposal.title).fontWeight(.semibold)
            }
            if note == nil { Text("대상 노트를 찾을 수 없어요").foregroundStyle(theme.color(.text3)) }
            else if full { rows }
            else { Button(action: review) { rows }.buttonStyle(.plain).accessibilityLabel("미리보기") }
            if proposal.requiresReview == true { Text("노트가 바뀌었어요. 미리보기를 다시 확인해 주세요.").foregroundStyle(theme.color(.text2)) }
            HStack(spacing: theme.component(.agentRowInset)) {
                if !full { TextActionLink(theme: theme, title: "노트로 보기", symbol: "chevron.right", action: review) }
                Spacer(minLength: 0)
                if let conversation { Button("대화 열기", action: conversation) }
                if pending {
                    Button("버리기", action: discard)
                    if proposal.requiresReview == true { Button("다시 미리보기", action: review) }
                    else { Button("받기", action: accept).disabled(note == nil) }
                } else { Text(proposal.status.label).foregroundStyle(theme.color(.text3)) }
            }.buttonStyle(WhiteControl(theme: theme))
        }.font(theme.font(.body, size: theme.component(.agentInputFont))).foregroundStyle(theme.color(.text))
            .padding(.leading, theme.component(.agentHeaderInset)).padding(.trailing, theme.space(.sp3))
            .padding(.vertical, theme.component(.agentInputInset))
            .proposalBackground(theme, pending: pending, radius: theme.shape(.windowRadius))
    }

    private var rows: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(note?.title.isEmpty == false ? note!.title : "제목 없음")
                .font(theme.font(.rowSub)).foregroundStyle(theme.color(.text3))
            let values = preview
            ForEach(Array((full ? values[...] : values.prefix(3)).enumerated()), id: \.offset) { _, row in
                HStack(spacing: theme.space(.sp1)) {
                    Text(row.1 ? "+" : "").frame(width: theme.component(.rowHeight))
                    if row.0.hasPrefix("[ ] ") || row.0.hasPrefix("[x] ") {
                        Image(systemName: row.0.hasPrefix("[x] ") ? "checkmark.square" : "square")
                        Text(String(row.0.dropFirst(4)))
                    } else { Text(row.0) }
                    Spacer(minLength: 0)
                }.frame(minHeight: theme.component(.agentStepHeight))
                    .background(row.1 ? theme.color(.highlight3Background) : .clear)
            }
        }.padding(.horizontal, theme.component(.agentInputInset)).padding(.vertical, theme.space(.sp2))
            .background(theme.color(.surface2), in: RoundedRectangle(cornerRadius: theme.space(.sp2)))
    }
}
