import AppKit

/// 플로팅 노트 창(spec 4.1, 19). 앱을 앞으로 가져오지 않고 키 창이 되며, 모든 Spaces와 전체 화면 앱 위에 보인다.
final class NotePanelWindow: NSPanel {
    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.nonactivatingPanel, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        hidesOnDeactivate = false
        isFloatingPanel = true
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

    /// 확인용 실행에서 끈다. 꺼져 있으면 키 창이 되지 않아 사용자가 다른 앱에 치던 글자를 가져오지 않는다.
    /// (`NotePanelCoordinator.allowsKeyWindows`가 넣는다. 그쪽이 `@_spi(Verification)`으로 가려져 있다.)
    var allowsKey = true

    /// 사용자가 이 창 안을 눌렀다(왼쪽 버튼). 키 창이 되는 것과 따로 알린다(이미 키 창이면 키 창 알림이 오지 않는다).
    var onMouseDown: (() -> Void)?

    /// 앱이 시켜서 키 창이 되려 한 횟수. 시험이 "시켰는지"를 본다(시험에서는 실제로 키 창이 되지 않게 꺼 둔다).
    private(set) var keyRequestCount = 0

    private var isKeyRequested = false

    /// 제목 막대가 없는 창은 기본으로 키 창이 되지 못한다. 글을 쓰려면 되어야 한다.
    ///
    /// 노트 창은 앱이 앞에 있지 않아도 키 창이 되어 키 입력을 받는다. 그래서 다음 때에만 키 창이 된다(D-025).
    /// - 사용자가 이 창을 눌렀다(`mouseDown`).
    /// - 앱이 일부러 시켰다(`becomeKeyByRequest()`): 본문에 커서 두기, 제목 고치기, 다음 노트로, 새 노트,
    ///   키 창이던 노트가 내려가 다음 노트가 이어받기, 사용자가 앱을 앞으로 가져옴.
    /// - 손쉬운 사용 도구(VoiceOver 등)가 이 창에 포커스를 달라고 했다(아래 `setAccessibilityFocused` 등).
    ///
    /// 앱을 켜며 되살린 창, "모두 보이기"로 돌아온 창, 마우스만 올린 창은 저절로 키 창이 되지 않아
    /// 다른 앱에 치던 글자를 가져오지 않는다.
    override var canBecomeKey: Bool {
        canBecomeKey(during: NSApplication.shared.currentEvent)
    }

    /// - Parameter event: 지금 처리 중인 이벤트. 이 창을 누른 것이면 키 창이 될 수 있다.
    func canBecomeKey(during event: NSEvent?) -> Bool {
        guard allowsKey else { return false }
        if isKeyRequested || isKeyWindow { return true }
        guard let event, [.leftMouseDown, .rightMouseDown, .otherMouseDown].contains(event.type) else { return false }
        return event.windowNumber == windowNumber
    }

    /// 앱이 시켜서 키 창이 된다.
    func becomeKeyByRequest() {
        keyRequestCount += 1
        allowingKey { makeKeyAndOrderFront(nil) }
    }

    /// `work`를 하는 동안에는 키 창이 될 수 있다.
    private func allowingKey<T>(_ work: () -> T) -> T {
        let wasRequested = isKeyRequested
        isKeyRequested = true
        defer { isKeyRequested = wasRequested }
        return work()
    }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .leftMouseDown { onMouseDown?() }
        super.sendEvent(event)
    }

    // MARK: - 손쉬운 사용

    // VoiceOver 같은 도구는 창 요소에 AXFocused, AXMain을 넣거나 AXRaise를 시켜 창으로 옮겨 온다.
    // 이것은 사용자가 이 창을 고른 것이므로 누른 것과 같이 받는다. AppKit은 이 요청을 아래 세 곳으로 넘긴다.
    //
    // 창이 아니라 창 안의 요소(본문 텍스트 뷰 등)에 온 포커스 요청은 여기서 가려낼 수 없다. 그 요청은 그 뷰의
    // `setAccessibilityFocused`로 가고, AppKit이 거기서 부르는 `makeKeyWindow`는 여느 호출과 구별되는 표시가
    // 없다(`canBecomeKey`가 불릴 때 손쉬운 사용 요청 중인지 알려 주는 공개 API가 없다).

    override func setAccessibilityFocused(_ accessibilityFocused: Bool) {
        allowingKey { super.setAccessibilityFocused(accessibilityFocused) }
        if accessibilityFocused, !isKeyWindow { becomeKeyByRequest() }
    }

    override func setAccessibilityMain(_ accessibilityMain: Bool) {
        allowingKey { super.setAccessibilityMain(accessibilityMain) }
        // 노트 창은 주 창이 되지 않는다. 주 창으로 삼으려는 요청은 키 창으로 받는다.
        if accessibilityMain, !isKeyWindow { becomeKeyByRequest() }
    }

    override func accessibilityPerformRaise() -> Bool {
        allowingKey { super.accessibilityPerformRaise() }
    }

    override var canBecomeMain: Bool { false }

    /// 핀이 켜지면 다른 앱 위에 뜬다. 끄면 보통 창처럼 뒤로 갈 수 있다.
    func setPinned(_ pinned: Bool) {
        isFloatingPanel = pinned
        level = pinned ? .floating : .normal
    }
}
