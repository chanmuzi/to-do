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
                shape.strokeBorder(theme.color(.agentDash), style: StrokeStyle(lineWidth: theme.shape(.borderWidth),
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
    package let spaceName: String?
    package let full: Bool
    package let review: () -> Void
    package let conversation: (() -> Void)?
    package let accept: () -> Void
    package let discard: () -> Void

    package init(theme: Theme, proposal: AgentProposal, note: Note?, full: Bool, spaceName: String? = nil, review: @escaping () -> Void,
                 conversation: (() -> Void)? = nil, accept: @escaping () -> Void, discard: @escaping () -> Void) {
        self.spaceName = spaceName
        self.theme = theme; self.proposal = proposal; self.note = note; self.full = full
        self.review = review; self.conversation = conversation; self.accept = accept; self.discard = discard
    }

    private var pending: Bool { proposal.status == .pending }
    private var missingNote: Bool { note == nil && proposal.createdNoteID == nil && proposal.target != .instructions }
    @ViewBuilder private var noteBody: some View {
        if case let .instructions(before, after) = proposal.content {
            InstructionPreview(theme: theme, before: before, after: after)
        } else if case .newNote(_, let markdown) = proposal.content {
            ProposalNoteBody(theme: theme, markdown: markdown, addedLines: pending ? nil : 0, compact: !full)
        } else if let note {
            let additions = pending ? proposal.lines : []
            let markdown = additions.reduce(note.body) { TodoAppender.append($1, to: $0) }
            ProposalNoteBody(theme: theme, markdown: markdown, addedLines: additions.count, compact: !full)
        }
    }

    package var body: some View {
        VStack(alignment: .leading, spacing: theme.space(.sp2)) {
            HStack(spacing: theme.component(.agentChipInset)) {
                AgentFace(theme: theme, state: .done)
                Text(proposal.title).fontWeight(.semibold)
            }
            if missingNote { Text("대상 노트를 찾을 수 없어요").foregroundStyle(theme.color(.text3)) }
            else if full {
                rows.padding(theme.component(.agentInputInset))
                    .proposalBackground(theme, pending: pending, radius: theme.shape(.windowRadius))
            }
            else { Button(action: review) { rows }.buttonStyle(.plain).accessibilityLabel("미리보기") }
            if proposal.requiresReview == true { Text(proposal.target == .instructions ? "지침이 바뀌었어요. 미리보기를 다시 확인해 주세요." : "노트가 바뀌었어요. 미리보기를 다시 확인해 주세요.").foregroundStyle(theme.color(.text2)) }
            HStack(spacing: theme.component(.agentRowInset)) {
                if !full { TextActionLink(theme: theme, title: "노트로 보기", symbol: "chevron.right", action: review) }
                Spacer(minLength: 0)
                if let conversation { Button("대화 열기", action: conversation) }
                if pending {
                    Button("버리기", action: discard)
                    if proposal.requiresReview == true { Button("다시 미리보기", action: review) }
                    else { Button("받기", action: accept).disabled(missingNote) }
                } else { Text(proposal.status.label).foregroundStyle(theme.color(.text3)) }
            }.buttonStyle(WhiteControl(theme: theme))
        }.font(theme.font(.body, size: theme.component(.proposalFont))).foregroundStyle(theme.color(.text))
            .padding(.leading, theme.component(.agentHeaderInset)).padding(.trailing, theme.space(.sp3))
            .padding(.vertical, theme.component(.agentInputInset))
            .background { if !full { Color.clear.proposalBackground(theme, pending: pending, radius: theme.shape(.windowRadius)) } }
    }

    private var previewTitle: String {
        if proposal.target == .instructions { return "지침, 받은 뒤" }
        if case .newNote(let title, _) = proposal.content { return title }
        return note.flatMap { $0.title.isEmpty ? nil : $0.title } ?? "제목 없음"
    }

    @ViewBuilder private var rows: some View {
        if let item = proposal.scheduleItem {
            ScheduleProposalPreview(theme: theme, note: note, proposed: item, pending: pending, full: full)
        } else { textRows }
    }

    private var textRows: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(previewTitle)
                .font(theme.font(.rowSub)).foregroundStyle(theme.color(.text3)).padding(.horizontal, theme.space(.sp3))
            if let spaceName { Text(spaceName).font(theme.font(.micro)).padding(.horizontal, theme.space(.sp3)) }
            noteBody
        }.padding(.vertical, theme.space(.sp2))
            .background(theme.color(.surface), in: RoundedRectangle(cornerRadius: theme.space(.sp2)))
    }
}
