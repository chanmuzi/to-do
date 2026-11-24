import SwiftUI
import Models
import Theme

struct AgentWindowView: View {
    let theme: Theme
    var modelPicker: ((Bool, CommandLineSpace) -> AnyView)?
    @State private var inputHovered = false
    @State private var lineSpace: CommandLineSpace?
    let title: String
    let draft: AgentDraft
    let history: () -> [AgentConversation]
    let openHistory: (UUID) -> Void
    let newChat: () -> Void
    @State private var selection: UUID?
    @State private var editingTitle = false
    @State private var editedName = ""
    let delete: () -> Void
    let send: () -> Void
    let sendAll: () -> Void
    let retry: (UUID) -> Void
    let sendNow: (UUID) -> Void
    var openProposal: (UUID) -> Void = { _ in }
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
            if draft.showsHistory {
                ConversationHistoryList(theme: theme, conversations: history(), selection: $selection, open: openHistory)
            } else {
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
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: theme.component(.agentInputInset)) {
                            ForEach(draft.conversation.requests) { request in
                                AgentTurnView(theme: theme, draft: draft, request: request, still: still,
                                              openNote: openNote, openProposal: openProposal, noteTitle: titleForNote, retry: { retry(request.id) }).id(request.id)
                            }
                        }.frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, theme.component(.agentHeaderInset)).padding(.vertical, theme.space(.sp3))
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { conversationHeight = $0 }
                    }
                    .scrollPosition($position)
                    .defaultScrollAnchor(.bottom, for: .initialOffset)
                    .defaultScrollAnchor(.top, for: .alignment)
                    .defaultScrollAnchor(followsBottom ? .bottom : nil, for: .sizeChanges)
                    .onScrollGeometryChange(for: Viewport.self) { geometry in
                        Viewport(offset: geometry.visibleRect.minY, bottom: geometry.visibleRect.maxY,
                                 height: geometry.contentSize.height, viewport: geometry.containerSize.height)
                    } action: { previous, current in
                        // 글이나 창의 크기만 변한 경우는 사용자가 위로 올린 것이 아니다.
                        #if DEBUG
                        draft.scrollMetrics = ["offset": current.offset, "bottom": current.bottom, "content": current.height,
                                               "viewport": current.viewport]
                        #endif
                        if current.atBottom { followsBottom = true }
                        else if previous.height == current.height && previous.viewport == current.viewport &&
                                    previous.offset != current.offset {
                            followsBottom = false
                        } else if followsBottom { position.scrollTo(edge: .bottom) }
                    }
                    #if DEBUG
                    .onChange(of: draft.verificationBottom) {
                        if let bottom = draft.verificationBottom {
                            position.scrollTo(edge: bottom ? .bottom : .top)
                            draft.verificationBottom = nil
                        }
                    }
                    #endif
                    .overlay(alignment: .bottom) {
                        if !followsBottom {
                            Button {
                                followsBottom = true
                                position.scrollTo(edge: .bottom)
                            } label: {
                                let side = theme.component(.agentScrollButton)
                                let shadow = theme.shadow(.pop).last
                                Image(systemName: "arrow.down")
                                    .font(.system(size: theme.component(.iconMedium)))
                                    .foregroundStyle(theme.color(.text2))
                                    .frame(width: side, height: side)
                                    .background(theme.color(.surface), in: Circle())
                                    .shadow(color: shadow?.color.color ?? .clear, radius: (shadow?.blur ?? 0) / 2, y: shadow?.y ?? 0)
                            }.buttonStyle(.plain).accessibilityLabel("맨 아래로").help("맨 아래로")
                                .padding(.bottom, theme.space(.sp2))
                        }
                    }
                        .onChange(of: draft.evidenceRequest, initial: true) {
                            if let id = draft.evidenceRequest {
                                proxy.scrollTo(id, anchor: .top)
                                draft.evidenceRequest = nil
                            }
                        }
                }
                if !draft.conversation.queued.isEmpty {
                    if draft.queueHeld {
                        AgentQueueHeader(theme: theme, count: draft.conversation.queued.count, remove: {
                            if draft.change({ $0.queued.removeAll() }) { draft.queueHeld = false }
                        }, send: sendAll)
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { headerHeight = $0 }
                    }
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
                HStack(spacing: theme.space(.sp2)) {
                    CommandTextField(text: Binding(get: { draft.conversation.draft }, set: draft.update), theme: theme,
                                     placeholder: "에이전트에게 요청하기", font: theme.nsFont(.body, size: theme.component(.agentInputFont)),
                                     wraps: true, submit: send, cancel: close)
                        .onLineSpaceChange { lineSpace = $0 }
                        .overlay(alignment: lineSpace?.multiline == true ? .bottomTrailing : .trailing) {
                            if let modelPicker, let lineSpace {
                                modelPicker(showsModel, lineSpace)
                            }
                        }
                    control("보내기", .send, action: draft.conversation.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : send)
                }
                .padding(.leading, theme.component(.agentInputInset))
                .padding(.trailing, theme.space(.sp1))
                .frame(minHeight: theme.shape(.chromeHeight))
                .overlay(RoundedRectangle(cornerRadius: theme.space(.sp2)).strokeBorder(theme.color(.outline), lineWidth: theme.shape(.borderWidth)))
                .contentShape(Rectangle())
                .onHover { inputHovered = $0 }
                .padding([.horizontal, .bottom], theme.space(.sp3))
            }
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

    private var showsModel: Bool {
        #if DEBUG
        if let preview = draft.previewInputHover { return preview }
        #endif
        return inputHovered
    }

    private struct Viewport: Equatable {
        let offset: CGFloat
        let bottom: CGFloat
        let height: CGFloat
        let viewport: CGFloat
        var atBottom: Bool { bottom.rounded(.up) >= height.rounded(.down) }
    }
    @State private var position = ScrollPosition(edge: .bottom)
    @State private var followsBottom = true
    @State private var conversationHeight: CGFloat = 0
    @State private var headerHeight: CGFloat = 0
    private var queueHeight: CGFloat {
        CGFloat(draft.conversation.queued.count) * (theme.component(.iconButton) + theme.component(.iconButtonGap))
            - theme.component(.iconButtonGap)
    }
    private var queueLimit: CGFloat { theme.component(.scheduleListMaxHeight) }
    private var requiredHeight: CGFloat {
        let targetHeight = draft.conversation.targets.isEmpty ? 0 : theme.component(.iconButton) + theme.space(.sp2)
        let heldHeight = draft.queueHeld && !draft.conversation.queued.isEmpty ? headerHeight : 0
        return conversationHeight + heldHeight + targetHeight + theme.shape(.chromeHeight) * 2 + theme.space(.sp3)
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
            AgentFace(theme: theme, state: draft.conversation.requests.last?.face ?? .idle, forceStill: still).padding(.trailing, theme.component(.agentFaceTitleGap) - theme.component(.iconButtonGap))
            if editingTitle {
                CommandTextField(text: $editedName, theme: theme, placeholder: "대화 이름", style: .title, submit: {
                    if draft.rename(editedName) { editingTitle = false }
                }, cancel: { editingTitle = false })
                .frame(height: theme.lineHeight(.title))
            } else {
                Text(draft.showsHistory ? "지난 대화" : !draft.conversation.hasSubmitted ? "에이전트" : draft.conversation.name).lineLimit(1).font(theme.font(.title)).foregroundStyle(theme.color(.text))
            }
            Spacer(minLength: 0)
            control("지난 대화", .clock) { draft.showsHistory.toggle() }
            control("새 대화", .plus, action: newChat)
            ConversationMenu(theme: theme, id: draft.conversation.id, enabled: draft.conversation.hasSubmitted,
                             rename: {
                                 draft.showsHistory = false
                                 editedName = draft.conversation.name
                                 editingTitle = true
                             }, delete: delete)
                .frame(width: theme.component(.iconButton), height: theme.component(.iconButton))
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
