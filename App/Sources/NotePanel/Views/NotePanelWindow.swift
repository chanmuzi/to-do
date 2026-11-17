import AppKit

/// 플로팅 노트 창(spec 4.1, 19). 보통 앱 창처럼 누르면 앱이 앞으로 오고 키 창이 된다(D-025).
/// 모든 Spaces와 전체 화면 앱 위에 보이고, 앱이 뒤로 가도 숨지 않는다.
final class NotePanelWindow: NSPanel {
    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        hidesOnDeactivate = false
        isFloatingPanel = true
        becomesKeyOnlyIfNeeded = false
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        // 창은 상단 줄로만 끈다. 본문을 끌면 글자 선택이다.
        isMovableByWindowBackground = false
        isReleasedWhenClosed = false
        isRestorable = false
        animationBehavior = .none
    }

    /// 확인용 실행과 시험에서 끈다. 꺼져 있으면 키 창이 되지 않는다.
    /// (`NotePanelCoordinator.allowsKeyWindows`가 넣는다. 그쪽이 `@_spi(Verification)`으로 가려져 있다.)
    var allowsKey = true

    /// 사용자가 이 창 안을 눌렀다(왼쪽 버튼). 키 창이 되는 것과 따로 알린다(이미 키 창이면 키 창 알림이 오지 않는다).
    var onMouseDown: (() -> Void)?

    /// 사용자가 이 창의 버튼(`ClickableView`)을 누르기 시작했다. 앱이 앞에 있지 않으면 앞으로 가져온다
    /// (보통 창을 누른 것과 같다. 버튼으로 가는 누름은 AppKit의 창 처리를 거치지 않으므로 따로 알린다).
    var onButtonPress: (() -> Void)?

    /// 앱이 시켜서 키 창이 되려 한 횟수. 시험이 "시켰는지"를 본다(시험에서는 실제로 키 창이 되지 않게 꺼 둔다).
    private(set) var keyRequestCount = 0

    /// 지금 누르고 있는 버튼. 뗄 때까지의 이벤트를 이 버튼이 받는다.
    private weak var pressedButton: ClickableView?

    /// 제목 막대가 없는 창은 기본으로 키 창이 되지 못한다. 글을 쓰려면 되어야 한다.
    ///
    /// 노트 창은 앱을 앞으로 가져오는 보통 창이라, 키 창이어도 앱이 뒤에 있는 동안에는 키 입력을 받지 않는다.
    /// 그래서 언제 키 창이 되는지를 따로 막지 않는다. 다른 앱의 입력을 가져오지 않는 일은 앱을 앞으로 가져오는
    /// 쪽이 지킨다: 켤 때 되살린 창, "노트 모두 보이기"로 돌아온 창, 마우스만 올린 창은 앱을 앞으로 가져오지 않는다.
    override var canBecomeKey: Bool { allowsKey }

    override var canBecomeMain: Bool { false }

    /// 앱이 시켜서 키 창이 된다(본문에 커서 두기, 제목 고치기, 다음 노트로, 새 노트, 키 창 이어받기).
    func becomeKeyByRequest() {
        keyRequestCount += 1
        makeKeyAndOrderFront(nil)
    }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .leftMouseDown { onMouseDown?() }
        if deliverToButton(event) { return }
        super.sendEvent(event)
    }

    /// 버튼으로 가는 누름과 그 뒤의 끌기, 뗌은 창이 다른 일을 하기 전에 그 버튼에 곧바로 건넨다.
    ///
    /// AppKit에 맡기면 두 곳에서 누름이 사라졌다. 테두리 없는 창의 모서리 근처는 크기 조절 자리라 그 안의 버튼
    /// (오른쪽 위의 핀, 오른쪽 아래의 닫기)을 누르면 창이 크기 조절을 시작했고, 키 창이 아니거나 앱이 뒤에 있을 때의
    /// 첫 누름은 누른 뷰가 `acceptsFirstMouse`로 받겠다고 해야 전달되었다.
    /// - Returns: 버튼이 받았으면 참.
    private func deliverToButton(_ event: NSEvent) -> Bool {
        switch event.type {
        case .leftMouseDown:
            // 앞선 누름의 뗌이 이 창에 오지 않았을 수 있다(창이 내려감 등). 남은 버튼을 먼저 잊는다.
            pressedButton = nil
            guard let button = button(at: event.locationInWindow) else { return false }
            pressedButton = button
            if allowsKey, !isKeyWindow { makeKeyAndOrderFront(nil) }
            onButtonPress?()
            button.mouseDown(with: event)
            return true
        case .leftMouseDragged:
            guard let button = pressedButton, button.window === self else { return false }
            button.mouseDragged(with: event)
            return true
        case .leftMouseUp:
            guard let button = pressedButton, button.window === self else {
                pressedButton = nil
                return false
            }
            pressedButton = nil
            button.mouseUp(with: event)
            return true
        default:
            return false
        }
    }

    /// 창 좌표의 그 점에서 누름을 받을 버튼.
    func button(at pointInWindow: NSPoint) -> ClickableView? {
        guard let content = contentView, let frameView = content.superview else { return nil }
        return content.hitTest(frameView.convert(pointInWindow, from: nil)) as? ClickableView
    }

    /// 핀이 켜지면 다른 앱 위에 뜬다. 끄면 보통 창처럼 뒤로 갈 수 있다.
    func setPinned(_ pinned: Bool) {
        isFloatingPanel = pinned
        level = pinned ? .floating : .normal
    }
}
