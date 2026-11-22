import SwiftUI
import Theme

struct SettingsPreview: View {
    let theme: Theme
    let values: SettingsValues
    private var lineHeight: CGFloat { theme.lineHeight(.body) }
    private var fontSize: CGFloat { theme.noteBodySize }
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: theme.space(.sp1)) {
                Text("오늘 할 일").font(theme.font(.title))
                Spacer()
                Group {
                    if values.spaceDisplay != "name" { Image(systemName: "folder") }
                    if values.spaceDisplay != "icon" { Text("개인") }
                }.modifier(PreviewFlash(theme: theme, value: values.spaceDisplay))
            }.font(theme.font(.ui)).padding(.horizontal, theme.space(.sp3)).frame(height: theme.component(.settingsPreviewHead))
            separator
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: theme.space(.sp2)) {
                    check(true)
                    Text("치과 예약 전화").strikethrough().foregroundStyle(theme.color(.text3))
                }.frame(height: lineHeight)
                HStack(spacing: theme.space(.sp2)) {
                    check(false)
                    HStack(spacing: theme.space(.sp1)) {
                        Text("보고서에").underline(values.markedTextStyle == .underline)
                            .modifier(PreviewFlash(theme: theme, value: values.markedTextStyle))
                        Text("git log").font(theme.font(.code, size: fontSize))
                            .padding(.horizontal, theme.component(.codePaddingX))
                            .foregroundStyle(theme.color(values.inlineCode == "plain" ? .codeForeground : .codeAccent))
                            .background(theme.color(.codeBackground), in: RoundedRectangle(cornerRadius: theme.shape(.codeRadius)))
                            .modifier(PreviewFlash(theme: theme, value: values.inlineCode))
                        Text("붙이기")
                    }
                }.frame(height: lineHeight)
            }.font(theme.font(.body, size: fontSize))
                .modifier(PreviewFlash(theme: theme, value: [fontSize, lineHeight]))
                .padding(.horizontal, theme.space(.sp4)).padding(.vertical, theme.space(.sp3))
            if values.formatBar != "hidden" {
                separator
                HStack(spacing: theme.space(.sp3)) {
                    Text("B").bold()
                    Text("S").strikethrough()
                    Text("H")
                    Text("링크")
                    Text("코드")
                }.font(theme.font(.micro)).foregroundStyle(theme.color(.text2))
                    .padding(.horizontal, theme.space(.sp3)).frame(height: theme.component(.settingsPreviewFoot))
            }
        }.frame(width: theme.component(.settingsPreviewWidth))
            .background(theme.color(.surface), in: RoundedRectangle(cornerRadius: theme.shape(.windowRadius)))
            .overlay { RoundedRectangle(cornerRadius: theme.shape(.windowRadius)).strokeBorder(theme.color(.line)) }
            .modifier(PreviewFlash(theme: theme, value: [values.appearance, values.formatBar, String(values.recognizesDates)]))
            .padding(.vertical, theme.space(.sp4)).frame(maxWidth: .infinity)
            .background(theme.color(.surface2), in: RoundedRectangle(cornerRadius: theme.shape(.windowRadius)))
            .allowsHitTesting(false).focusable(false)
            .accessibilityHidden(true)
            .background { PreviewAccessibilityImage() }
    }

    private var separator: some View { Rectangle().fill(theme.color(.line)).frame(height: theme.shape(.borderWidth)) }
    private func check(_ done: Bool) -> some View {
        Group {
            if values.checkbox == "bracket" { Text(done ? "[x]" : "[ ]") }
            else { Image(systemName: done ? "checkmark.square.fill" : "square") }
        }.font(.system(size: theme.component(.checkSize))).modifier(PreviewFlash(theme: theme, value: values.checkbox))
    }
}

/// VoiceOver에는 샘플 전체를 이미지 하나로 제공한다.
private struct PreviewAccessibilityImage: NSViewRepresentable {
    final class SampleImage: NSView {
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
        override var acceptsFirstResponder: Bool { false }
    }
    func makeNSView(context: Context) -> SampleImage {
        let image = SampleImage()
        image.setAccessibilityElement(true)
        image.setAccessibilityRole(.image)
        image.setAccessibilityLabel("노트 미리보기")
        return image
    }
    func updateNSView(_ view: SampleImage, context: Context) {}
}

private struct PreviewFlash<Value: Equatable>: ViewModifier {
    let theme: Theme
    let value: Value
    @Environment(\.accessibilityReduceMotion) private var reduced
    @State private var changed = false
    @State private var generation = 0
    func body(content: Content) -> some View {
        content.overlay {
            if changed && !reduced {
                RoundedRectangle(cornerRadius: theme.shape(.controlRadius))
                    .strokeBorder(theme.color(.text2), lineWidth: theme.component(.iconButtonGap)).allowsHitTesting(false)
            }
        }.onChange(of: value) {
            changed = !reduced
            generation += 1
        }.task(id: generation) {
            guard changed else { return }
            do { try await Task.sleep(for: .seconds(theme.motion.settingsFlash)); changed = false }
            catch { }
        }
    }
}
