import AppKit
import Theme

/// 캡처 바의 뷰가 테마 값을 꺼내는 한 곳. 접근성 설정(대비 증가, 동작 줄이기)을 여기서 반영한다(spec 15, 17).
struct CaptureStyle {
    let theme: Theme

    private var increasesContrast: Bool { NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast }
    private var reducesMotion: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

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

    /// 전환 시간. "동작 줄이기"가 켜져 있으면 바로 바꾼다.
    var transitionDuration: TimeInterval { reducesMotion ? 0 : theme.motion.duration }

    /// 알파를 `dur`, `ease`로 바꾼다(규칙 8). `completion`은 움직임이 끝난 뒤에 불린다.
    func animate(_ changes: () -> Void, completion: (@MainActor () -> Void)? = nil) {
        guard transitionDuration > 0 else {
            changes()
            completion?()
            return
        }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = transitionDuration
            context.timingFunction = theme.motion.timingFunction
            context.allowsImplicitAnimation = true
            changes()
        }, completionHandler: completion.map { completion in
            { @Sendable in MainActor.assumeIsolated { completion() } }
        })
    }

    /// SF Symbols 아이콘(spec 18.2). 굵기는 regular, 크기는 토큰.
    func symbol(_ name: String, size: ComponentToken) -> NSImage? {
        let configuration = NSImage.SymbolConfiguration(pointSize: theme.component(size), weight: .regular)
        return NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(configuration)
    }

    /// 글자 칸(`NSTextField`)이 글자 좌우에 두는 고정 여백. 시스템 값이지 디자인 값이 아니다.
    /// 간격 토큰이 글자 사이에 그대로 보이도록 배치할 때 이만큼을 뺀다.
    static let labelInset: CGFloat = 2

    /// 글자 칸에 글이 잘리지 않고 들어가는 크기. 칸 안쪽 여백까지 센다.
    func fittingSize(of label: NSTextField) -> NSSize {
        guard let size = label.cell?.cellSize else { return label.intrinsicContentSize }
        return NSSize(width: size.width.rounded(.up), height: size.height.rounded(.up))
    }

    /// 글자만의 너비(칸 안쪽 여백을 뺀 것).
    func textWidth(of label: NSTextField) -> CGFloat {
        max(0, fittingSize(of: label).width - Self.labelInset * 2)
    }

    /// 글자가 `textX`에서 시작해 `textWidth`만큼 보이도록, 세로로는 `height`의 가운데에 칸을 놓는다.
    func labelFrame(_ label: NSTextField, textX: CGFloat, textWidth: CGFloat, centeredIn height: CGFloat) -> NSRect {
        let labelHeight = fittingSize(of: label).height
        return NSRect(
            x: textX - Self.labelInset, y: ((height - labelHeight) / 2).rounded(),
            width: max(0, textWidth) + Self.labelInset * 2, height: labelHeight
        )
    }

    /// 캡처 입력 글꼴(Pretendard `fs-capture`).
    var inputFont: NSFont { theme.nsFont(.capture) }

    /// 맨 앞의 `>`: D2Coding을 입력 글자 크기로.
    var promptFont: NSFont { theme.nsFont(.code, size: theme.tokens.textStyle(.capture).size) }
}
