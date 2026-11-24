import MarkdownSyntax
import SwiftUI
import Theme

struct AgentAnswerView: View {
    let theme: Theme
    let answer: String

    var body: some View {
        let document = MarkdownDocument(answer)
        VStack(alignment: .leading, spacing: 0) {
            ForEach(document.lines.indices, id: \.self) { index in
                let line = document.lines[index]
                switch line.kind {
                case .fenceClose, .fenceOpen: EmptyView()
                case .code:
                    Text(verbatim: document.string(in: line.range)).font(theme.font(.code))
                default:
                    let source = document.string(in: line.range)
                    let text = (try? AttributedString(markdown: source)) ?? AttributedString(source)
                    let intents = text.runs.first?.presentationIntent?.components ?? []
                    let number = intents.compactMap { intent -> Int? in
                        if case let .listItem(ordinal) = intent.kind { return ordinal }
                        return nil
                    }.first
                    let ordered = intents.contains { $0.kind == .orderedList }
                    let heading = intents.contains { if case .header = $0.kind { true } else { false } }
                    HStack(alignment: .firstTextBaseline, spacing: 0) {
                        if let number {
                            Text(ordered ? "\(number)." : "•")
                                .frame(minWidth: theme.component(.agentListIndent), alignment: .center)
                        }
                        Text(text).fontWeight(heading ? .semibold : nil)
                    }
                    .frame(minHeight: theme.component(.agentAnswerLine), alignment: .leading)
                    .padding(.top, heading && index > 0 ? theme.component(.agentHeadingGap) : 0)
                }
            }
        }.textSelection(.enabled)
    }
}
