import AppKit
import SwiftUI
import Theme

struct LibraryButtonStyle: ButtonStyle {
    let theme: Theme
    var selected = false
    var rounded = true
    var icon = false
    var hoverName = ""
    func makeBody(configuration: Configuration) -> some View {
        LibraryButtonBody(hoverName: hoverName, theme: theme, selected: selected, rounded: rounded, icon: icon, pressed: configuration.isPressed,
                          label: configuration.label)
    }
}
private struct LibraryButtonBody<Label: View>: View {
    let hoverName: String
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
            .background {
                if !hoverName.isEmpty { LibrarySidebarHover(name: hoverName) { hovered = $0 && enabled } }
            }
            .background(selected ? theme.libraryColor(.selected) : ((hovered || pressed) && enabled ? theme.libraryColor(.hover) : .clear))
            .clipShape(RoundedRectangle(cornerRadius: rounded ? theme.shape(icon ? .chipRadius : .controlRadius) : 0))

            .accessibilityAddTraits(selected ? .isSelected : [])
            .onHover { hovered = $0 && enabled }
            .animation(NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? nil : theme.motion.animation,
                       value: hovered || pressed || selected)
    }
}

// 대비 증가에서는 흐린 보조 글자와 경계도 읽을 수 있게 한다(spec 17).
extension Theme {
    var libraryNumberFont: Font {
        font(.body, size: tokens.textStyle(.micro).size).monospacedDigit()
    }

    func libraryColor(_ token: ColorToken, on background: ColorToken = .surface2) -> Color {
        guard NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast else { return color(token, on: background) }
        return color(token == .text3 ? .text2 : token == .line ? .outline : token, on: background)
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

/// 창 안의 추적 영역만 사용한다. 디버그 검사도 같은 mouseEntered 경로를 지난다.
struct LibrarySidebarHover: NSViewRepresentable {
    let name: String
    let changed: (Bool) -> Void
    func makeNSView(context: Context) -> SidebarHoverView { SidebarHoverView() }
    func updateNSView(_ view: SidebarHoverView, context: Context) {
        view.changed = changed; view.setAccessibilityLabel(name + " 호버")
    }
}
final class SidebarHoverView: NSView {
    var changed: (Bool) -> Void = { _ in }
    private var area: NSTrackingArea?
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let area { removeTrackingArea(area) }
        let value = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self)
        addTrackingArea(value); area = value
    }
    override func mouseEntered(with event: NSEvent) { changed(true) }
    override func mouseExited(with event: NSEvent) { changed(false) }
}
