import SwiftUI
import Theme

/// 테마가 실제로 먹는지 눈으로 확인하는 임시 화면. NotePanel이 생기면 지운다.
struct PlaceholderView: View {
    let theme: Theme
    let noteCount: Int
    let notesPath: String

    var body: some View {
        VStack(alignment: .leading, spacing: theme.space(.sp3)) {
            Text("플로팅 노트")
                .font(theme.font(.h1))
                .tracking(theme.tracking(.h1))
            Text("본문은 Pretendard입니다. The quick brown fox 0123456789")
                .font(theme.font(.body))
            Text("굵게 650 · 보조 글자")
                .font(theme.font(.strong))
                .foregroundStyle(theme.color(.text2))
            Text("D2Coding 15:00 · 3/7 · let note = Note()")
                .font(theme.font(.code))
                .padding(.horizontal, theme.space(.sp1))
                .foregroundStyle(theme.color(.codeForeground))
                .background(
                    theme.color(.codeBackground),
                    in: RoundedRectangle(cornerRadius: theme.shape(.codeRadius))
                )
            highlights
            palette
            Text("\(theme.appearance.rawValue) · 노트 \(noteCount)개 · \(notesPath)")
                .font(theme.font(.micro))
                .foregroundStyle(theme.color(.text3))
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .foregroundStyle(theme.color(.text))
        .padding(theme.space(.sp4))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(theme.color(.surface))
    }

    private var highlights: some View {
        HStack(spacing: theme.space(.sp2)) {
            ForEach(HighlightColor.allCases, id: \.self) { highlight in
                Text("형광펜 \(highlight.rawValue)")
                    .font(theme.font(.body))
                    .foregroundStyle(theme.color(highlight.foreground))
                    .background(
                        theme.color(highlight.background),
                        in: RoundedRectangle(cornerRadius: theme.shape(.highlightRadius))
                    )
            }
        }
    }

    private var palette: some View {
        HStack(spacing: theme.space(.sp1)) {
            ForEach(theme.palette) { entry in
                RoundedRectangle(cornerRadius: theme.shape(.chipRadius))
                    .fill(theme.noteBackgroundColor(paletteID: entry.id))
                    .strokeBorder(theme.color(.outline), lineWidth: theme.shape(.borderWidth))
                    .frame(height: theme.component(.rowHeight))
            }
        }
    }
}
