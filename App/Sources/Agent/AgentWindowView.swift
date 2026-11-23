import SwiftUI
import Theme

struct AgentWindowView: View {
    let theme: Theme
    let title: String
    let draft: AgentDraft
    let close: () -> Void

    var body: some View {
        let outline = RoundedRectangle(cornerRadius: theme.shape(.windowRadius))
        VStack(alignment: .leading, spacing: 0) {
            header
            HStack(spacing: theme.component(.agentChipGap)) {
                Image(nsImage: AgentWindowGlyph.note.image(theme: theme)).renderingMode(.template).foregroundStyle(theme.color(.text2))
                Text(title).lineLimit(1)
            }
            .font(theme.font(.body, size: theme.tokens.textStyle(.micro).size))
            .foregroundStyle(theme.color(.text))
            .padding(.horizontal, theme.component(.agentChipInset))
            .frame(height: theme.component(.agentFaceLarge))
            .background(theme.color(.surface2), in: RoundedRectangle(cornerRadius: theme.shape(.chipRadius)))
            .padding(.leading, theme.component(.agentHeaderInset))
            .padding(.top, theme.space(.sp2))

            Spacer(minLength: 0)
            if let error = draft.errorMessage {
                Text(error).font(theme.font(.ui)).foregroundStyle(theme.color(.warn)).padding(.horizontal, theme.space(.sp3))
            }
            HStack(spacing: theme.space(.sp1)) {
                CommandTextField(text: Binding(get: { draft.conversation.draft }, set: draft.update), theme: theme,
                                 placeholder: "에이전트에게 요청하기", font: theme.nsFont(.body, size: theme.component(.agentInputFont)),
                                 submit: {}, cancel: close)
                control("보내기", .send)
            }
            .padding(.leading, theme.component(.agentInputInset))
            .padding(.trailing, theme.space(.sp1))
            .frame(height: theme.shape(.chromeHeight))
            .overlay(RoundedRectangle(cornerRadius: theme.space(.sp2)).strokeBorder(theme.color(.outline), lineWidth: theme.shape(.borderWidth)))
            .padding([.horizontal, .bottom], theme.space(.sp3))
        }
        .padding(theme.component(.agentEdgeIdle))
        .background(theme.color(.surface), in: outline)
        .overlay(outline.strokeBorder(LinearGradient(colors: [theme.color(.agentEdgeA), theme.color(.agentEdgeB)],
                                                     startPoint: .init(x: 0, y: 0.2), endPoint: .init(x: 1, y: 0.8)),
                                      lineWidth: theme.component(.agentEdgeIdle)).allowsHitTesting(false))
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
            AgentFace(theme: theme).padding(.trailing, theme.component(.agentFaceTitleGap) - theme.component(.iconButtonGap))
            Text("에이전트").font(theme.font(.title)).foregroundStyle(theme.color(.text))
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
