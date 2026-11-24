import Models
import SwiftUI
import Theme

extension AgentRequest {
    package var progressTitle: String {
        activeStep?.title(for: .active) ?? face.rawValue
    }

    private var activeStep: Step? { steps.last { $0.endedAt == nil } }

    package var face: AgentFaceState {
        switch status {
        case .running: activeStep?.kind.face ?? .think
        case .completed: .done
        case .interrupted: .idle
        case .failed: .blocked
        case .awaitingAnswer: .ask
        }
    }
}

struct AgentTurnView: View {
    let theme: Theme
    let draft: AgentDraft
    let request: AgentRequest
    let still: Bool
    let openNote: (NoteID) -> Void
    var openProposal: (UUID) -> Void = { _ in }
    var noteTitle: (NoteID) -> String? = { _ in nil }
    let retry: () -> Void

    private var expanded: Bool { draft.expanded.contains(request.id) }
    private var summary: String {
        if request.status == .running { return request.progressTitle }
        let count = Set(request.steps.compactMap(\.noteID)).count
        return count > 0 ? "노트 \(count)개 읽음" : "진행 \(request.steps.count)단계"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: theme.component(.agentInputInset)) {
            Text(request.userText)
                .padding(.horizontal, theme.component(.agentBubbleInset)).padding(.vertical, theme.component(.agentRowInset))
                .background(theme.color(.agentMessage), in: RoundedRectangle(cornerRadius: theme.space(.sp3)))
                .frame(maxWidth: .infinity, alignment: .trailing)
            ForEach(request.stoppedAttempts ?? []) { attempt in
                HStack(alignment: .top, spacing: 0) {
                    AgentFace(theme: theme, state: .idle, forceStill: still)
                        .frame(width: theme.component(.agentAnswerFaceSlot), alignment: .leading)
                    VStack(alignment: .leading, spacing: theme.component(.agentRowInset)) {
                        if !attempt.steps.isEmpty { stepList(attempt.steps, status: .interrupted) }
                        if let answer = attempt.answer { AgentAnswerView(theme: theme, answer: answer) }
                        stoppedLine("앱을 끄면서 멈췄어요")
                    }
                }
            }
            HStack(alignment: .top, spacing: 0) {
                AgentFace(theme: theme, state: request.face, forceStill: still)
                    .frame(width: theme.component(.agentAnswerFaceSlot), alignment: .leading)
                VStack(alignment: .leading, spacing: theme.component(.agentRowInset)) {
                    if request.status == .running || !request.steps.isEmpty {
                        Button {
                            if expanded { draft.expanded.remove(request.id) } else { draft.expanded.insert(request.id) }
                        } label: {
                            HStack(spacing: theme.component(.agentChipGap)) {
                                symbol("chevron.right", size: .iconSmall)
                                    .rotationEffect(.degrees(expanded ? 90 : 0))
                                    .animation(still ? nil : theme.motion.animation, value: expanded)
                                    .progressFrame("chevron", draft: draft)
                                if request.status == .running && !still {
                                    TimelineView(.animation) { timeline in
                                        let t = timeline.date.timeIntervalSinceReferenceDate / theme.tokens.period(.agentShimmerPeriod)
                                        let x = (t - floor(t)) * 2 - 1
                                        Text(summary).foregroundStyle(LinearGradient(colors: [theme.color(.text3),
                                            theme.color(.agentShimmer), theme.color(.text3)],
                                            startPoint: .init(x: x, y: 0), endPoint: .init(x: x + 1, y: 0)))
                                    }
                                } else { Text(summary) }
                            }.font(smallFont)
                                .frame(maxWidth: .infinity, minHeight: theme.component(.agentProgressHeight), alignment: .leading)
                                .contentShape(Rectangle())
                        }.buttonStyle(SettingsButton(theme: theme, selected: false, showsHover: previewHover == "summary"))
                            .accessibilityValue(expanded ? "펼쳐짐" : "접힘")
                    }
                    if expanded { stepList(request.steps, status: request.status) }
                    if let answer = request.answer {
                        AgentAnswerView(theme: theme, answer: answer)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .progressFrame("answer", draft: draft)
                    }
                    ForEach(request.proposals) { proposal in
                        Button { openProposal(proposal.id) } label: {
                            HStack(spacing: theme.space(.sp2)) {
                                Text(proposal.title)
                                if let id = proposal.targetID { Text(noteTitle(id) ?? id.rawValue).lineLimit(1) }
                                Spacer(minLength: 0)
                                Text(proposal.target == .instructions && proposal.status == .pending ? "메모리" : proposal.createdNoteID != nil && proposal.status == .pending ? "제안" : proposal.status.label).font(smallFont).foregroundStyle(theme.color(.text3))
                            }.padding(.horizontal, theme.component(.agentInputInset))
                                .frame(minHeight: theme.component(.proposalLinkHeight))
                                .proposalBackground(theme, pending: proposal.status == .pending, radius: theme.space(.sp2))
                                .contentShape(Rectangle())
                        }.buttonStyle(.plain)
                    }
                    if request.status == .interrupted {
                        stoppedLine(request.stopReason == .shutdown ? "앱을 끄면서 멈췄어요" : "여기서 멈췄어요")
                    }
                    if request.status == .failed {
                        stoppedLine(request.failure ?? "막혔어요")
                        if let reset = request.resumeTime { Text("\(reset)부터 다시 돼요").font(smallFont) }
                        Button("다시 시도", action: retry).buttonStyle(SettingsButton(theme: theme, selected: false))
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
        }.font(theme.font(.body, size: theme.component(.agentInputFont)))
            .foregroundStyle(theme.color(.text))
            .onChange(of: request.status) { if request.status != .running { draft.expanded.remove(request.id) } }
    }

    private var smallFont: Font { theme.font(.body, size: theme.tokens.textStyle(.micro).size) }

    private func stoppedLine(_ text: String) -> some View {
        Text(text).font(smallFont).foregroundStyle(theme.color(.text3))
            .frame(minHeight: theme.component(.agentProgressHeight))
    }

    private var previewHover: String? {
        #if DEBUG
        draft.previewProgressHover
        #else
        nil
        #endif
    }

    @ViewBuilder private func symbol(_ name: String, size: ComponentToken) -> some View {
        if let image = theme.symbolImage(name, size: size) {
            Image(nsImage: image).renderingMode(.template)
                .frame(width: theme.component(size), height: theme.component(size)).accessibilityHidden(true)
        }
    }

    private func stepList(_ steps: [AgentRequest.Step], status: AgentRequest.Status) -> some View {
        VStack(alignment: .leading, spacing: theme.component(.iconButtonGap)) {
            ForEach(steps, id: \.id) { step in
                let phase = step.phase(in: status, last: step.id == steps.last?.id)
                let title = step.title(for: phase)
                HStack(alignment: .firstTextBaseline, spacing: theme.component(.agentRowInset)) {
                    Group {
                        switch phase {
                        case .completed: symbol("checkmark", size: .valueMenuCheck)
                        case .failed: symbol("xmark", size: .valueMenuCheck)
                        case .active, .stopped: Color.clear
                        }
                    }.frame(width: theme.component(.valueMenuCheck), height: theme.component(.valueMenuCheck))
                        .accessibilityHidden(true)
                    Group {
                        if let note = step.noteID {
                            TextActionLink(theme: theme, title: title, minimumHeight: theme.component(.agentStepHeight),
                                           showsHover: previewHover == "link") { openNote(note) }
                        } else { Text(title) }
                    }.progressBaseline("label-" + step.id.uuidString, draft: draft)
                    Spacer(minLength: 0)
                    if let duration = step.durationLabel {
                        Text(duration).fixedSize().monospacedDigit()
                            .progressBaseline("time-" + step.id.uuidString, draft: draft)
                            .progressFrame("time-" + step.id.uuidString, draft: draft)
                    }
                }.frame(minHeight: theme.component(.agentStepHeight))
                    .progressFrame("row-" + step.id.uuidString, draft: draft)
            }
        }.font(smallFont).foregroundStyle(theme.color(.text2))
            .padding(.leading, theme.component(.iconSmall) + theme.component(.agentChipGap))
            .overlay(alignment: .leading) {
                Rectangle().fill(theme.color(.line)).frame(width: theme.shape(.borderWidth))
                    .progressFrame("rail", draft: draft)
                    .frame(width: theme.component(.iconSmall)).allowsHitTesting(false)
            }
    }
}
