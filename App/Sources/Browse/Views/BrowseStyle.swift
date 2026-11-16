import AppKit
import Theme

/// 노트 찾기의 뷰가 테마 값을 꺼내는 한 곳. 접근성 설정(대비 증가, 동작 줄이기)을 여기서 반영한다(spec 15, 17).
struct BrowseStyle {
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

    func cgColor(_ token: ColorToken, in view: NSView) -> CGColor {
        cgColor(color(token), in: view)
    }

    /// 전환 시간. "동작 줄이기"가 켜져 있으면 바로 바꾼다.
    var transitionDuration: TimeInterval { reducesMotion ? 0 : theme.motion.duration }

    /// 알파, 창 틀을 `dur`, `ease`로 바꾼다(규칙 8). "동작 줄이기"면 시간이 0이라 바로 바뀐다.
    ///
    /// 움직임이 끝났을 때를 알려 주지 않는다. 끝난 뒤에 할 일(창 내리기, 끝의 틀에 놓기)은 `afterTransition`으로
    /// 잡는다: 화면이 꺼져 있으면 창의 움직임은 나아가지 않고 끝났다는 알림도 오지 않는다.
    func animate(_ changes: () -> Void) {
        let duration = transitionDuration
        NSAnimationContext.runAnimationGroup { context in
            // 시간이 0이어도 묶는다: `animator()`로 바꾼 값이 시스템 기본 시간으로 움직이지 않게.
            context.duration = duration
            if duration > 0 {
                context.timingFunction = theme.motion.timingFunction
                context.allowsImplicitAnimation = true
            }
            changes()
        }
    }

    /// 전환 시간이 지난 뒤에 `work`를 한다("동작 줄이기"면 그 자리에서). 돌려받은 것을 취소하면 하지 않는다.
    func afterTransition(_ work: @escaping @MainActor () -> Void) -> Task<Void, Never>? {
        TransitionTimer.after(transitionDuration, work)
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

    // MARK: - 글꼴 (spec 8)

    private var regularWeight: CGFloat { theme.tokens.textStyle(.body).weight }

    /// 줄 제목: `fs-row`, 굵기 600.
    var titleFont: NSFont { theme.nsFont(.row) }
    /// "제목 없음", 검색 칸, 새 노트 만들기, 라이브러리 열기: `fs-row`, 보통 굵기.
    var plainFont: NSFont { theme.nsFont(.row, weight: regularWeight) }
    /// 본문 첫머리: `fs-row-sub`.
    var previewFont: NSFont { theme.nsFont(.rowSub) }
    /// 본문에서 맞은 낱말: 같은 크기에 굵기 600.
    var previewMatchFont: NSFont { theme.nsFont(.rowSub, weight: theme.tokens.textStyle(.title).weight) }
    /// 구획 이름: Pretendard를 `fs-micro` 크기로.
    var headerFont: NSFont { theme.nsFont(.body, size: theme.tokens.textStyle(.micro).size) }
    /// 리마인더: D2Coding `fs-micro`. 임박은 굵게.
    func reminderFont(strong: Bool) -> NSFont {
        strong ? theme.nsFont(.micro, weight: theme.tokens.textStyle(.uiStrong).weight) : theme.nsFont(.micro)
    }

    // MARK: - 치수

    /// 줄 안쪽 좌우 여백(`sp-2`).
    var rowPadding: CGFloat { theme.space(.sp2) }
    /// 줄 맨 앞과 맨 뒤의 아이콘 칸 너비.
    var leadWidth: CGFloat { theme.component(.iconLarge) }
    /// 구획 이름의 높이: 위 `sp-2`, 글자 `lh-micro`, 아래 검색 칸 아래와 같은 틈.
    var headerHeight: CGFloat {
        theme.space(.sp2) + theme.lineHeight(.micro) + theme.component(.browseFindGap)
    }
    /// 구분선 자리의 높이: 선 위아래로 안쪽 여백만큼.
    var separatorHeight: CGFloat {
        theme.component(.browsePadding) * 2 + theme.shape(.borderWidth)
    }
}
