import SwiftUI
import Models
import Theme

struct AgentWindowView: View {
    let theme: Theme
    let title: String
    let draft: AgentDraft
    let send: () -> Void
    let retry: (UUID) -> Void
    let sendNow: (UUID) -> Void
    let openNote: (NoteID) -> Void
    let chooseTarget: () -> Void
    let titleForNote: (NoteID) -> String?
    let fit: (CGFloat) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var still: Bool {
        #if DEBUG
        if draft.still { return true }
        #endif
        return reduceMotion
    }
    private var working: Bool { draft.conversation.requests.last?.status == .running }
    let close: () -> Void

    var body: some View {
        let outline = RoundedRectangle(cornerRadius: theme.shape(.windowRadius))
        VStack(alignment: .leading, spacing: 0) {
            header
            if !draft.conversation.targets.isEmpty {
                HStack(spacing: theme.space(.sp1)) {
                    ForEach(draft.conversation.targets, id: \.self) { id in
                        HStack(spacing: theme.component(.agentChipGap)) {
                            Image(nsImage: AgentWindowGlyph.note.image(theme: theme))
                            Text(titleForNote(id) ?? title).lineLimit(1)
                        }
                        .font(theme.font(.body, size: theme.tokens.textStyle(.micro).size))
                        .padding(.horizontal, theme.component(.agentChipInset))
                        .frame(height: theme.component(.agentFaceLarge))
                        .background(theme.color(.surface2), in: RoundedRectangle(cornerRadius: theme.shape(.chipRadius)))
                    }
                    control("대상 추가", .plus, action: chooseTarget)
                }.padding(.leading, theme.component(.agentHeaderInset)).padding(.top, theme.space(.sp2))
            }
            ScrollView {
                VStack(alignment: .leading, spacing: theme.component(.agentInputInset)) {
                    ForEach(draft.conversation.requests) { request in
                        AgentTurnView(theme: theme, draft: draft, request: request, still: still,
                                      openNote: openNote, retry: { retry(request.id) })
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, theme.component(.agentHeaderInset)).padding(.vertical, theme.space(.sp3))
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { conversationHeight = $0 }
            }.defaultScrollAnchor(.bottom)
            if !draft.conversation.queued.isEmpty {
                ScrollView {
                    VStack(spacing: theme.component(.iconButtonGap)) {
                        ForEach(draft.conversation.queued) { item in
                            AgentQueueRow(theme: theme, draft: draft, item: item, sendNow: { sendNow(item.id) })
                        }
                    }
                }.frame(height: min(queueHeight, queueLimit))
                .padding(.horizontal, theme.space(.sp3)).padding(.bottom, theme.component(.agentRowInset))
            }
            if let error = draft.errorMessage {
                Text(error).font(theme.font(.ui)).foregroundStyle(theme.color(.warn)).padding(.horizontal, theme.space(.sp3))
            }
            HStack(spacing: theme.space(.sp1)) {
                CommandTextField(text: Binding(get: { draft.conversation.draft }, set: draft.update), theme: theme,
                                 placeholder: "에이전트에게 요청하기", font: theme.nsFont(.body, size: theme.component(.agentInputFont)),
                                 submit: send, cancel: close)
                control("보내기", .send, action: draft.conversation.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : send)
            }
            .padding(.leading, theme.component(.agentInputInset))
            .padding(.trailing, theme.space(.sp1))
            .frame(height: theme.shape(.chromeHeight))
            .overlay(RoundedRectangle(cornerRadius: theme.space(.sp2)).strokeBorder(theme.color(.outline), lineWidth: theme.shape(.borderWidth)))
            .padding([.horizontal, .bottom], theme.space(.sp3))
        }
        .padding(theme.component(.agentEdgeIdle))
        .background(theme.color(.surface), in: outline)
        .overlay {
            TimelineView(.animation(paused: !working || still)) { timeline in
                let t = timeline.date.timeIntervalSinceReferenceDate / theme.tokens.period(.agentEdgePeriod)
                let shift = working && !still ? (1 - cos(t * 2 * .pi)) / 2 : 0
                outline.strokeBorder(LinearGradient(colors: [theme.color(.agentEdgeA), theme.color(.agentEdgeB)],
                    startPoint: .init(x: shift, y: 0.2), endPoint: .init(x: 1 - shift, y: 0.8)),
                    lineWidth: theme.component(working ? .agentEdgeWorking : .agentEdgeIdle))
                    .shadow(color: theme.color(.agentEdgeA).opacity(working ? 0.2 : 0), radius: theme.component(.agentEdgeGlow))
            }.allowsHitTesting(false)
        }
        .onChange(of: requiredHeight) { _, height in fit(height) }
    }

    @State private var conversationHeight: CGFloat = 0
    private var queueHeight: CGFloat {
        CGFloat(draft.conversation.queued.count) * (theme.component(.iconButton) + theme.component(.iconButtonGap))
            - theme.component(.iconButtonGap)
    }
    private var queueLimit: CGFloat { theme.component(.scheduleListMaxHeight) }
    private var requiredHeight: CGFloat {
        let targetHeight = draft.conversation.targets.isEmpty ? 0 : theme.component(.iconButton) + theme.space(.sp2)
        return conversationHeight + targetHeight + theme.shape(.chromeHeight) * 2 + theme.space(.sp3)
            + max(0, min(queueHeight, queueLimit) + theme.component(.agentRowInset)) + theme.component(.agentEdgeIdle) * 2
    }

    private func control(_ title: String, _ glyph: AgentWindowGlyph, action: (() -> Void)? = nil) -> some View {
        Button { action?() } label: {
            Image(nsImage: glyph.image(theme: theme)).renderingMode(.template)
                .frame(width: theme.component(.iconButton), height: theme.component(.iconButton))
        }.buttonStyle(SettingsButton(theme: theme, selected: false))
            .disabled(action == nil).accessibilityLabel(title)
    }

    private var header: some View {
        HStack(spacing: theme.component(.iconButtonGap)) {
            AgentFace(theme: theme, state: draft.conversation.requests.last?.face ?? .idle).padding(.trailing, theme.component(.agentFaceTitleGap) - theme.component(.iconButtonGap))
            Text(draft.conversation.requests.isEmpty ? "에이전트" : draft.conversation.name).lineLimit(1).font(theme.font(.title)).foregroundStyle(theme.color(.text))
            Spacer(minLength: 0)
            control("지난 대화", .clock)
            control("새 대화", .plus)
            control("더 보기", .more)
            Rectangle().fill(theme.color(.line)).frame(width: theme.shape(.borderWidth), height: theme.component(.iconMedium))
                .padding(.horizontal, theme.space(.sp1))
            control("창 닫기", .close, action: close)
        }
        .padding(.leading, theme.component(.agentHeaderInset))
        .padding(.trailing, theme.component(.chromePaddingEnd))
        .frame(height: theme.shape(.chromeHeight))
        .overlay(alignment: .bottom) { Rectangle().fill(theme.color(.line)).frame(height: theme.shape(.borderWidth)) }
    }
}
