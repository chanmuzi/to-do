import AppKit
import SwiftUI
import Theme

struct LibraryButtonStyle: ButtonStyle {
    let theme: Theme
    var selected = false
    var rounded = true
    var icon = false
    func makeBody(configuration: Configuration) -> some View {
        LibraryButtonBody(theme: theme, selected: selected, rounded: rounded, icon: icon, pressed: configuration.isPressed,
                          label: configuration.label)
    }
}
private struct LibraryButtonBody<Label: View>: View {
    let theme: Theme
    let selected: Bool
    let rounded: Bool
    let icon: Bool
    let pressed: Bool
    let label: Label
    @Environment(\.isEnabled) private var enabled
    @State private var hovered = false
    var body: some View {
        label.contentShape(Rectangle())
            .background(selected ? theme.libraryColor(.accent) : ((hovered || pressed) && enabled ? theme.libraryColor(.hover) : .clear))
            .clipShape(RoundedRectangle(cornerRadius: rounded ? theme.shape(icon ? .chipRadius : .controlRadius) : 0))
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
    @State private var hovered = false
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            LibrarySymbol(theme: theme, name: symbol, size: .iconLarge)
                .foregroundStyle(theme.libraryColor(enabled ? (hovered ? .text : .text2) : .text3))
                .frame(width: theme.component(.libraryToolbarButton), height: theme.component(.libraryToolbarButton))
        }.buttonStyle(LibraryButtonStyle(theme: theme, icon: true)).disabled(!enabled).accessibilityLabel(title)
            .onHover { hovered = $0 && enabled }
            .animation(NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? nil : theme.motion.animation, value: hovered)
    }
}

// 대비 증가에서는 흐린 보조 글자와 경계도 읽을 수 있게 한다(spec 17).
extension Theme {
    func libraryColor(_ token: ColorToken) -> Color {
        guard NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast else { return color(token) }
        return color(token == .text3 ? .text2 : token == .line ? .outline : token)
    }
}

/// 노트 상단과 같은 광학 보정과 크기 토큰을 쓴다. 그림만 작아지고 누름 영역은 그대로다.
struct LibrarySymbol: View {
    let theme: Theme
    let name: String
    let size: ComponentToken
    var body: some View {
        if let image = theme.symbolImage(name, size: size) {
            Image(nsImage: image).renderingMode(.template)
                .frame(width: theme.component(size), height: theme.component(size))
        }
    }
}

/// SwiftUI 포커스 효과와 별개인 AppKit 버튼/팝업의 기본 포커스 링도 없앤다.
/// 키 뷰 순서와 acceptsFirstResponder는 바꾸지 않는다.
final class LibraryHostingView<Content: View>: NSHostingView<Content> {
    override func layout() {
        super.layout()
        func suppressRing(_ view: NSView) {
            view.focusRingType = .none
            view.subviews.forEach(suppressRing)
        }
        suppressRing(self)
    }
}
