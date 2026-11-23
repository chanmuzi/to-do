import Models
import SwiftUI
import Theme

extension AgentRequest {
    package var face: AgentFaceState {
        switch status {
        case .running: steps.last?.kind.face ?? .think
        case .completed: .done
        case .interrupted: .idle
        case .failed: .blocked
        case .awaitingAnswer: .ask
        }
    }
}

private extension AgentRequest.Step.Kind {
    var face: AgentFaceState {
        switch self { case .think: .think; case .search: .search; case .read: .read; case .write: .write }
    }
}

struct AgentTurnView: View {
    let theme: Theme
    let draft: AgentDraft
    let request: AgentRequest
    let still: Bool
    let openNote: (NoteID) -> Void
    let retry: () -> Void

    private var expanded: Bool { draft.expanded.contains(request.id) }
    private var summary: String {
        if request.status == .running { return request.face.rawValue }
        let count = Set(request.steps.compactMap(\.noteID)).count
        return count > 0 ? "노트 \(count)개 읽음" : "진행 \(request.steps.count)단계"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: theme.component(.agentInputInset)) {
            Text(request.userText)
                .padding(.horizontal, theme.component(.agentBubbleInset)).padding(.vertical, theme.component(.agentRowInset))
                .background(theme.color(.surface2), in: RoundedRectangle(cornerRadius: theme.space(.sp3)))
                .frame(maxWidth: .infinity, alignment: .trailing)
            HStack(alignment: .top, spacing: 0) {
                AgentFace(theme: theme, state: request.face)
                    .frame(width: theme.component(.agentAnswerFaceSlot), alignment: .leading)
                VStack(alignment: .leading, spacing: theme.component(.agentRowInset)) {
                    if !request.steps.isEmpty {
                        Button {
                            if expanded { draft.expanded.remove(request.id) } else { draft.expanded.insert(request.id) }
                        } label: {
                            HStack(spacing: theme.component(.agentChipGap)) {
                                Image(systemName: expanded ? "chevron.down" : "chevron.right")
                                if request.status == .running && !still {
                                    TimelineView(.animation) { timeline in
                                        let t = timeline.date.timeIntervalSinceReferenceDate / theme.tokens.period(.agentShimmerPeriod)
                                        let x = (t - floor(t)) * 2 - 1
                                        Text(summary).foregroundStyle(LinearGradient(colors: [theme.color(.text3),
                                            theme.color(.text2), theme.color(.text3)],
                                            startPoint: .init(x: x, y: 0), endPoint: .init(x: x + 1, y: 0)))
                                    }
                                } else { Text(summary) }
                            }
                        }.buttonStyle(.plain).foregroundStyle(theme.color(.text3)).font(smallFont)
                    }
                    if expanded { steps }
                    if let answer = request.answer { Text(answer).textSelection(.enabled) }
                    if request.status == .interrupted {
                        Text("여기서 멈췄어요").font(smallFont).foregroundStyle(theme.color(.text3))
                            .frame(minHeight: theme.component(.agentProgressHeight))
                    }
                    if request.status == .failed {
                        Text(request.failure ?? "막혔어요").font(smallFont)
                        if let reset = request.resumeTime { Text(reset).font(smallFont) }
                        Button("다시 시도", action: retry).buttonStyle(SettingsButton(theme: theme, selected: false))
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
        }.font(theme.font(.body, size: theme.component(.agentInputFont)))
            .foregroundStyle(theme.color(.text))
            .onChange(of: request.status) { if request.status != .running { draft.expanded.remove(request.id) } }
    }

    private var smallFont: Font { theme.font(.body, size: theme.tokens.textStyle(.micro).size) }

    private var steps: some View {
        VStack(alignment: .leading, spacing: theme.component(.iconButtonGap)) {
            ForEach(request.steps, id: \.id) { step in
                HStack(spacing: theme.component(.agentRowInset)) {
                    if step.endedAt != nil { Image(systemName: step.result == "실패" ? "xmark" : "checkmark") }
                    if let note = step.noteID, let title = step.noteTitle {
                        Button(title) { openNote(note) }.buttonStyle(.plain).underline()
                    } else { Text(step.kind.face.rawValue) }
                    Spacer(minLength: 0)
                    if let elapsed = step.elapsed { Text("\(elapsed, specifier: "%.1f")초").monospacedDigit() }
                }.frame(minHeight: theme.component(.agentStepHeight))
            }
        }.font(smallFont).foregroundStyle(theme.color(.text2))
            .padding(.leading, theme.component(.agentInputInset))
            .overlay(alignment: .leading) { Rectangle().fill(theme.color(.line)).frame(width: theme.shape(.borderWidth)) }
    }
}
