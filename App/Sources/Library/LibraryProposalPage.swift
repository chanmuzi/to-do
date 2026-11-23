import Models
import SwiftUI
import Theme

struct ProposalDot: View {
    let theme: Theme
    var body: some View {
        Circle().fill(theme.color(.text)).frame(width: theme.component(.noticeDot), height: theme.component(.noticeDot))
            .accessibilityLabel("새 제안")
    }
}

struct LibraryProposalPage: View {
    let model: LibraryModel
    private var theme: Theme { model.theme }
    @State private var hovered: UUID?

    private func hovering(_ id: UUID) -> Bool {
        #if DEBUG
        if let preview = model.previewProposalHover { return preview == id }
        #endif
        return hovered == id
    }

    var body: some View {
        GeometryReader { layout in
            let narrow = layout.size.width + theme.component(.librarySidebarWidth) + theme.shape(.borderWidth) <= theme.component(.libraryMinWidth)
            HStack(alignment: .top, spacing: 0) {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(model.proposalRequests) { request in
                            header(request)
                            ForEach(request.proposals) { proposal in
                                row(proposal, narrow: narrow)
                                if narrow, model.selectedProposal == proposal.id { detail(proposal) }
                            }
                        }
                    }.padding(.horizontal, theme.space(.sp2))
                }.frame(maxWidth: narrow ? .infinity : theme.component(.noteWidth))
                if !narrow {
                    theme.color(.line).frame(width: theme.shape(.borderWidth))
                    ScrollView {
                        if let p = model.proposalRequests.flatMap(\.proposals).first(where: { $0.id == model.selectedProposal }) { detail(p) }
                    }.frame(maxWidth: .infinity)
                }
            }
        }
    }

    private func header(_ request: AgentRequest) -> some View {
        let pending = request.proposals.filter { $0.status == .pending }.map(\.id)
        return HStack(spacing: theme.component(.agentRowInset)) {
            Image(systemName: "bubble.left")
            Text(request.userText).lineLimit(1)
            Spacer(minLength: 0)
            if hovering(request.id), !pending.isEmpty {
                Button { model.acceptProposals(pending) } label: {
                    Canvas { context, size in
                        let k = size.width / 16
                        var path = Path()
                        path.move(to: .init(x: 1.5*k, y: 8.7*k))
                        path.addLine(to: .init(x: 4.3*k, y: 11.5*k))
                        path.addLine(to: .init(x: 9.5*k, y: 5.2*k))
                        path.move(to: .init(x: 8*k, y: 11*k))
                        path.addLine(to: .init(x: 8.6*k, y: 11.5*k))
                        path.addLine(to: .init(x: 14.5*k, y: 4.7*k))
                        context.stroke(path, with: .foreground, style: .init(lineWidth: k * 1.4, lineCap: .round, lineJoin: .round))
                    }.frame(width: theme.component(.iconMedium), height: theme.component(.iconMedium))
                        .frame(width: theme.component(.iconButton), height: theme.component(.iconButton))
                }.buttonStyle(SettingsButton(theme: theme, selected: false)).accessibilityLabel("모두 받기")
            } else if let date = request.proposals.first?.createdAt {
                Text(ReminderPresentation.clock(date, format: .koreanMeridiem, calendar: model.index.calendar))
                    .font(theme.font(.micro)).foregroundStyle(theme.color(.text3))
            }
        }.font(theme.font(.libraryListHeading)).padding(.horizontal, theme.space(.sp2))
            .frame(minHeight: theme.component(.rowHeight))
            .background(hovering(request.id) ? theme.color(.hover) : .clear, in: RoundedRectangle(cornerRadius: theme.shape(.controlRadius)))
            .onHover { track($0, request.id) }
            .accessibilityAction(named: "모두 받기") { model.acceptProposals(pending) }
    }

    private func row(_ p: AgentProposal, narrow: Bool) -> some View {
        let selected = model.selectedProposal == p.id
        let note = model.index.notes.first { $0.id == p.targetID }
        return HStack(spacing: theme.space(.sp2)) {
            VStack(alignment: .leading, spacing: theme.component(.libraryRowGap)) {
                Text(p.title).font(theme.font(.row))
                Text(note?.title ?? "대상 노트 없음").font(theme.font(.rowSub)).foregroundStyle(theme.color(.text3))
            }.lineLimit(1)
            Spacer()
            if p.status != .pending { Text(p.status.label).font(theme.font(.micro)).foregroundStyle(theme.color(.text3)) }
            else if p.seenAt == nil, !hovering(p.id) { ProposalDot(theme: theme).padding(.trailing, theme.space(.sp1)) }
        }.padding(.vertical, theme.component(.agentRowInset)).padding(.horizontal, theme.space(.sp2))
            .background(selected ? theme.color(.selected) : hovering(p.id) ? theme.color(.hover) : .clear,
                        in: RoundedRectangle(cornerRadius: theme.shape(.controlRadius)))
            .overlay {
                HistoryRowInput(id: p.id, contextMenu: false) { count in
                    if count == 2 { model.openProposal(p.id) }
                    else { model.selectProposal(p.id, collapsible: narrow) }
                }
            }.overlay(alignment: .trailing) {
                if hovering(p.id), p.status == .pending {
                    HStack(spacing: theme.component(.agentQueueActionGap)) {
                        ChromeIconButton(theme: theme, title: "버리기", symbol: "xmark") { model.discardProposal(p.id) }
                        ChromeIconButton(theme: theme, title: "받기", symbol: "checkmark") { model.acceptProposals([p.id]) }
                    }.padding(.trailing, theme.space(.sp1))
                }
            }.onHover { track($0, p.id) }
            .accessibilityElement(children: .contain).accessibilityLabel(p.title)
            .accessibilityAction { model.selectProposal(p.id, collapsible: narrow) }
            .accessibilityAction(named: "열기") { model.openProposal(p.id) }
    }

    private func track(_ inside: Bool, _ id: UUID) {
        if inside { hovered = id } else if hovered == id { hovered = nil }
    }

    private func detail(_ p: AgentProposal) -> some View {
        TodoProposalView(theme: theme, proposal: p, note: model.index.notes.first { $0.id == p.targetID }, full: true,
                         review: { model.reviewProposal(p.id) }, conversation: {
            if let c = model.conversations().first(where: { $0.requests.contains { $0.id == p.requestID } }) { model.openConversation(c.id) }
        }, accept: { model.acceptProposals([p.id]) }, discard: { model.discardProposal(p.id) })
            .padding(theme.space(.sp3))
    }
}
