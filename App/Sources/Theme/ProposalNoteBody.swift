import MarkdownSyntax
import SwiftUI

/// 제안 종류와 표시 위치에 관계없이 같은 본문 줄과 투두 칸을 그린다.
struct ProposalNoteBody: View {
    let theme: Theme
    let markdown: String
    /// nil이면 새 노트의 본문 전체가 추가 줄이다.
    var addedLines: Int? = 0
    var compact = false

    var body: some View {
        let document = MarkdownDocument(markdown)
        let count = document.lines.count - (document.lines.last?.range.length == 0 ? 1 : 0)
        let firstAdded = max(0, count - (addedLines ?? count))
        let start = compact ? firstAdded : 0
        let end = compact ? min(count, start + 3) : count
        VStack(alignment: .leading, spacing: 0) {
            ForEach(start..<end, id: \.self) { index in
                let line = document.lines[index], added = index >= firstAdded
                HStack(spacing: 0) {
                    Text(added ? "+" : "").frame(width: theme.component(.proposalGutter))
                    ProposalLineContent(theme: theme, line: line, document: document)
                        .padding(.leading, CGFloat(line.level) * theme.component(.indent))
                    Spacer(minLength: 0)
                }.padding(.trailing, theme.space(.sp3))
                    .frame(minHeight: theme.component(.proposalLineHeight))
                    .background(added ? theme.color(.diffAdd) : .clear)
            }
        }.font(theme.font(.body, size: theme.component(.proposalFont)))
    }

}

struct ProposalLineContent: View {
    let theme: Theme
    let line: MarkdownLine
    let document: MarkdownDocument

    private var text: String {
        var start = line.contentStart, value = ""
        for marker in line.markers {
            value += document.string(in: NSRange(location: start, length: marker.range.location - start))
            start = NSMaxRange(marker.range)
        }
        return value + document.string(in: NSRange(location: start, length: line.end - start))
    }

    @ViewBuilder var body: some View {
        if case .todo(let done) = line.kind {
            HStack(spacing: 0) {
                let shape = RoundedRectangle(cornerRadius: theme.shape(.checkRadius))
                ZStack {
                    if done {
                        shape.fill(theme.color(.text3))
                        Image(systemName: "checkmark").foregroundStyle(theme.color(.surface))
                    } else { shape.strokeBorder(theme.color(.text2), lineWidth: theme.component(.editorGlyphStroke)) }
                }.frame(width: theme.component(.checkSize), height: theme.component(.checkSize))
                    .frame(width: theme.component(.indent), alignment: .leading)
                Text(text).strikethrough(done)
            }
        } else if line.kind == .bullet {
            HStack(spacing: 0) {
                Circle().frame(width: theme.component(.editorBulletDot), height: theme.component(.editorBulletDot))
                    .frame(width: theme.component(.indent), alignment: .leading)
                Text(text)
            }
        } else if case .heading = line.kind {
            Text(text).fontWeight(.semibold)
        } else if line.kind != .fenceOpen && line.kind != .fenceClose { Text(text) }
    }
}
