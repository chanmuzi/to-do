import AppKit

/// 창 크기와 자리(spec 5.6, 19). 너비는 사용자가 끌어 바꾸고, 높이는 내용을 따라
/// 위쪽 가장자리를 고정한 채 아래로 늘거나 준다.
extension NoteWindowController: NSWindowDelegate {
    func applySizeLimits() {
        let policy = environment.sizePolicy
        panel.contentMinSize = NSSize(width: policy.minWidth, height: policy.minHeight)
        panel.contentMaxSize = NSSize(width: policy.maxWidth, height: .greatestFiniteMagnitude)
    }

    /// 내용 높이에 창 높이를 맞춘다. 한도(화면 높이의 몫, 화면 아래 끝)에 닿으면 거기서 멈추고 본문이 스크롤된다.
    func applyContentHeight(animated: Bool) {
        guard contentHeight > 0 else { return }
        let top = liveResizeTop ?? panel.frame.maxY
        let visible = (panel.screen ?? NSScreen.main)?.visibleFrame
        let target = environment.sizePolicy.frame(
            current: panel.frame, top: top, contentHeight: contentHeight,
            screenHeight: visible?.height ?? .greatestFiniteMagnitude,
            roomBelowTop: visible.map { top - $0.minY } ?? .greatestFiniteMagnitude
        )
        if let heightTarget {
            // 이미 그 높이로 가는 중이다.
            guard target.height != heightTarget else { return }
        } else {
            guard target.height != panel.frame.height || target.maxY != panel.frame.maxY else { return }
        }

        heightAnimation?.cancel()
        heightAnimation = nil
        let transition = HeightTransition(
            from: panel.frame.height, to: target.height,
            duration: environment.style.transitionDuration, curve: environment.theme.motion.curve
        )
        if animated, isShown, panel.isVisible, liveResizeTop == nil, !transition.isInstant {
            heightTarget = target.height
            heightAnimation = Task { [weak self] in await self?.run(transition) }
        } else {
            heightTarget = nil
            setHeight(target.height, top: top)
            panel.invalidateShadow()
        }
        if isShown { environment.recorder.recordFrame(noteID, frame: target) }
    }

    /// 높이만 바꾼다. 가로 자리와 너비는 그때의 창을 따르므로 움직이는 중에 창을 끌어도 어긋나지 않는다.
    private func setHeight(_ height: CGFloat, top: CGFloat) {
        let frame = panel.frame
        panel.setFrame(NSRect(x: frame.minX, y: top - height, width: frame.width, height: height), display: true)
    }

    private func run(_ transition: HeightTransition) async {
        let clock = ContinuousClock()
        let start = clock.now
        while !Task.isCancelled {
            let elapsed = (clock.now - start) / .seconds(1)
            setHeight(transition.height(at: elapsed), top: panel.frame.maxY)
            if elapsed >= transition.duration { break }
            try? await Task.sleep(for: Self.frameInterval)
        }
        guard !Task.isCancelled else { return }
        heightTarget = nil
        heightAnimation = nil
        panel.invalidateShadow()
        if isShown { environment.recorder.recordFrame(noteID, frame: panel.frame) }
    }

    /// 높이를 다시 그리는 간격. 화면 주사율보다 촘촘해도 창은 화면이 그릴 때만 그려진다.
    private static var frameInterval: Duration { .milliseconds(8) }

    private func recordFrameIfSettled() {
        guard isShown, heightTarget == nil, liveResizeTop == nil else { return }
        environment.recorder.recordFrame(noteID, frame: panel.frame)
    }

    // MARK: - NSWindowDelegate

    /// 사용자가 가장자리를 끌 때는 너비만 바뀐다. 높이는 내용이 정한다.
    func windowWillResize(_ sender: NSWindow, to frameSize: NSSize) -> NSSize {
        guard sender.inLiveResize else { return frameSize }
        return NSSize(width: environment.sizePolicy.clampedWidth(frameSize.width), height: sender.frame.height)
    }

    func windowWillStartLiveResize(_ notification: Notification) {
        liveResizeTop = panel.frame.maxY
    }

    func windowDidEndLiveResize(_ notification: Notification) {
        liveResizeTop = nil
        applyContentHeight(animated: false)
        panel.invalidateShadow()
        recordFrameIfSettled()
    }

    /// 투명한 창의 그림자는 내용의 모양에서 만들어 두고 다시 쓰인다. 크기가 바뀔 때마다(높이가 움직이는
    /// 동안의 매 단계, 가장자리를 끄는 동안) 다시 재게 해, 줄어든 창 밖에 옛 그림자가 남지 않게 한다.
    func windowDidResize(_ notification: Notification) {
        root.syncHover()
        root.syncButtonHover()
        panel.invalidateShadow()
    }

    func windowDidMove(_ notification: Notification) {
        root.syncHover()
        root.syncButtonHover()
        recordFrameIfSettled()
    }

    /// 화면이 바뀌면 높이 한도가 달라진다.
    func windowDidChangeScreen(_ notification: Notification) {
        applyContentHeight(animated: false)
    }

    /// 키 창이 되면 맨 앞에 온 것이다. 겹친 차례를 적고, 다른 프로그램이 고친 파일을 다시 읽게 한다.
    func windowDidBecomeKey(_ notification: Notification) {
        environment.recorder.recordFronted(noteID, openedAt: environment.now())
        coordinator?.noteWindowDidBecomeKey()
    }

    /// 포커스는 창 모습을 바꾸지 않는다(규칙 5). 고치던 제목만 마무리한다.
    func windowDidResignKey(_ notification: Notification) {
        root.topRow.endTitleEditing()
    }
}
