import AppKit
import SwiftUI
import Theme

struct LibraryButtonStyle: ButtonStyle {
    let theme: Theme
    var selected = false
    var rounded = true
    func makeBody(configuration: Configuration) -> some View {
        LibraryButtonBody(theme: theme, selected: selected, rounded: rounded, pressed: configuration.isPressed,
                          label: configuration.label)
    }
}
private struct LibraryButtonBody<Label: View>: View {
    let theme: Theme
    let selected: Bool
    let rounded: Bool
    let pressed: Bool
    let label: Label
    @Environment(\.isEnabled) private var enabled
    @State private var hovered = false
    var body: some View {
        label.contentShape(Rectangle())
            .background(selected ? theme.libraryColor(.accent) : ((hovered || pressed) && enabled ? theme.libraryColor(.hover) : .clear))
            .clipShape(RoundedRectangle(cornerRadius: rounded ? theme.shape(.controlRadius) : 0))
            .onHover { hovered = $0 && enabled }
            .animation(NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? nil : theme.motion.animation,
                       value: hovered || pressed || selected)
    }
}

struct LibraryIconButton: View {
    let theme: Theme
    let title: String
    let symbol: String
    var enabled = true
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: theme.component(.iconLarge)))
                .foregroundStyle(theme.libraryColor(enabled ? .text2 : .text3))
                .frame(width: theme.component(.libraryToolbarButton), height: theme.component(.libraryToolbarButton))
        }.buttonStyle(LibraryButtonStyle(theme: theme)).disabled(!enabled).accessibilityLabel(title)
    }
}

// 대비 증가에서는 흐린 보조 글자와 경계도 읽을 수 있게 한다(spec 17).
extension Theme {
    func libraryColor(_ token: ColorToken) -> Color {
        guard NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast else { return color(token) }
        return color(token == .text3 ? .text2 : token == .line ? .outline : token)
    }
}
