import SwiftUI
import Theme

struct AgentQueueHeader: View {
    let theme: Theme
    let count: Int
    let remove: () -> Void
    let send: () -> Void

    private var label: some View {
        Text("보내지 않은 요청 \(count)개")
            .font(theme.font(.body, size: theme.tokens.textStyle(.micro).size))
            .foregroundStyle(theme.color(.text3)).fixedSize()
    }
    private var actions: some View {
        HStack(spacing: theme.component(.chromeGap)) {
            Button("모두 빼기", action: remove)
            Button("모두 보내기", action: send)
        }.buttonStyle(WhiteControl(theme: theme, horizontalPadding: theme.space(.sp2))).fixedSize()
    }
    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: theme.component(.chromeGap)) {
                label
                Spacer(minLength: 0)
                actions
            }
            VStack(alignment: .leading, spacing: theme.space(.sp1)) {
                label
                actions.frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .padding(.leading, theme.component(.agentFaceLarge))
        .padding(.trailing, theme.space(.sp3)).padding(.bottom, theme.space(.sp1))
    }
}
