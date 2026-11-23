import Models
import SwiftUI
import Theme

struct AgentQueueRow: View {
    let theme: Theme
    let draft: AgentDraft
    let item: AgentConversation.Queued
    let sendNow: () -> Void
    @FocusState private var focused: Bool
    private var revealed: Bool { draft.hovered == item.id || focused }
    var body: some View {
        HStack(spacing: theme.space(.sp2)) {
            Text("다음").font(theme.font(.body, size: theme.component(.agentQueueLabel))).foregroundStyle(theme.color(.text3))
            Text(item.text).font(theme.font(.rowSub)).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: theme.component(.agentQueueActionGap)) {
                icon("고치기", "pencil", .iconMedium) { draft.remove(item.id, editing: true) }
                    .disabled(!draft.conversation.draft.isEmpty)
                icon("빼기", "xmark", .agentQueueRemoveSize) { draft.remove(item.id, editing: false) }
                Button(action: sendNow) {
                    Image(nsImage: AgentWindowGlyph.send.image(theme: theme)).renderingMode(.template)
                        .frame(width: theme.component(.agentQueueActionSize), height: theme.component(.agentQueueActionSize))
                }.buttonStyle(SettingsButton(theme: theme, selected: false)).accessibilityLabel("지금 보내기")
            }.opacity(revealed ? 1 : 0).allowsHitTesting(revealed)
        }.padding(.leading, theme.space(.sp2)).padding(.trailing, theme.space(.sp1))
            .frame(height: theme.component(.iconButton))
            .background(revealed ? theme.color(.hover) : .clear, in: RoundedRectangle(cornerRadius: theme.component(.agentRowInset)))
            .foregroundStyle(theme.color(revealed ? .text2 : .text3)).contentShape(Rectangle())
            .focusable().focused($focused)
            .onHover { inside in
                if inside { draft.hovered = item.id } else if draft.hovered == item.id { draft.hovered = nil }
            }
            .accessibilityAction(named: "지금 보내기", sendNow)
            .accessibilityAction(named: "빼기") { draft.remove(item.id, editing: false) }
            .accessibilityAction(named: "고치기") { draft.remove(item.id, editing: true) }
    }

    private func icon(_ label: String, _ symbol: String, _ size: ComponentToken, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: theme.component(size)))
                .frame(width: theme.component(.agentQueueActionSize), height: theme.component(.agentQueueActionSize))
        }.buttonStyle(SettingsButton(theme: theme, selected: false)).accessibilityLabel(label)
    }
}
