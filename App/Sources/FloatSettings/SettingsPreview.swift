import SwiftUI
import Theme

struct SettingsPreview: View {
    let theme: Theme
    let values: SettingsValues
    var body: some View {
        VStack(alignment: .leading, spacing: theme.space(.sp3)) {
            note("오늘 할 일", text: "치과 예약 전화", complete: false)
            note("미리 보기", text: "변경된 색 확인", complete: true)
        }
        .padding(theme.space(.sp4)).frame(width: theme.component(.settingsPreviewWidth))
        .frame(maxHeight: .infinity).background(theme.color(.surface2)).accessibilityElement(children: .contain)
    }

    private func note(_ title: String, text: String, complete: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: theme.space(.sp1)) {
                if values.spaceDisplay != "name" { Image(systemName: "folder") }
                if values.spaceDisplay != "icon" { Text("개인") }
                Text(title)
            }.font(theme.font(.title)).foregroundStyle(theme.color(.text2))
                .frame(height: theme.shape(.chromeHeight))
            Rectangle().fill(theme.color(.line)).frame(height: theme.shape(.borderWidth))
            HStack(spacing: theme.space(.sp2)) {
                if values.checkbox == "bracket" {
                    Text(complete ? "[x]" : "[ ]").font(theme.font(.code))
                } else {
                    Image(systemName: complete ? "checkmark.square.fill" : "square")
                        .font(.system(size: theme.component(.checkSize)))
                }
                Text(text).font(theme.font(.body)).strikethrough(complete)
                if complete {
                    Text("code").font(theme.font(.code))
                        .foregroundStyle(theme.color(values.inlineCode == "plain" ? .codeForeground : .codeAccent))
                        .padding(.horizontal, theme.component(.codePaddingX))
                        .background(theme.color(.codeBackground), in: RoundedRectangle(cornerRadius: theme.shape(.codeRadius)))
                }
            }.frame(minHeight: theme.lineHeight(.body)).padding(.vertical, theme.space(.sp2))
        }.padding(.horizontal, theme.space(.sp3)).frame(maxWidth: .infinity, alignment: .leading)
            .background(theme.color(.surface), in: RoundedRectangle(cornerRadius: theme.shape(.windowRadius)))
    }
}
