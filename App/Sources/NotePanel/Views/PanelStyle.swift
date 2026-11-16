import AppKit
import Theme

/// 노트 창의 뷰가 테마 값을 꺼내는 한 곳. 접근성 설정(대비 증가, 동작 줄이기)을 여기서 반영한다(spec 15, 17).
struct PanelStyle {
    let theme: Theme

    private var increasesContrast: Bool { NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast }
    var reducesMotion: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

    /// "대비 증가"가 켜져 있으면 `text-3`를 `text-2`로, `line`을 `outline`으로 바꾼다.
    func color(_ token: ColorToken) -> NSColor {
        guard increasesContrast else { return theme.nsColor(token) }
        switch token {
        case .text3: return theme.nsColor(.text2)
        case .line: return theme.nsColor(.outline)
        default: return theme.nsColor(token)
        }
    }

    /// 레이어에 넣을 색. 그 뷰의 라이트·다크로 푼다.
    func cgColor(_ color: NSColor, in view: NSView) -> CGColor {
        var resolved = CGColor.clear
        view.effectiveAppearance.performAsCurrentDrawingAppearance { resolved = color.cgColor }
        return resolved
    }

    func cgColor(_ token: ColorToken, in view: NSView) -> CGColor {
        cgColor(color(token), in: view)
    }

    /// 전환 시간. "동작 줄이기"가 켜져 있으면 바로 바꾼다.
    var transitionDuration: TimeInterval { reducesMotion ? 0 : theme.motion.duration }

    /// 알파와 레이어 색을 `dur`, `ease`로 바꾼다(규칙 8).
    func animate(_ changes: () -> Void) {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = transitionDuration
            context.timingFunction = theme.motion.timingFunction
            context.allowsImplicitAnimation = true
            changes()
        }
    }

    /// 글자색, 아이콘 색처럼 따로 움직일 수 없는 속성을 바꾸기 직전에 부른다. 바뀐 모습으로 `dur` 동안 넘어간다.
    func crossfade(_ view: NSView) {
        guard transitionDuration > 0, let layer = view.layer else { return }
        let transition = CATransition()
        transition.type = .fade
        transition.duration = transitionDuration
        transition.timingFunction = theme.motion.timingFunction
        layer.add(transition, forKey: "panel.crossfade")
    }

    /// SF Symbols 아이콘(spec 18.2). 굵기는 regular, 크기는 토큰.
    func symbol(_ name: String, size: ComponentToken) -> NSImage? {
        let configuration = NSImage.SymbolConfiguration(pointSize: theme.component(size), weight: .regular)
        return NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(configuration)
    }
}
