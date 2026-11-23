import AppKit

/// 시스템 입력기의 구간과 선택을 유지하면서 앱에서 정한 조합 모양을 사용한다.
@MainActor
open class PlainTextInputView: NSTextView {
    private var windowResignation: NSObjectProtocol?

    open override func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {
        guard let attributed = string as? NSAttributedString else {
            super.setMarkedText(string, selectedRange: selectedRange, replacementRange: replacementRange)
            return
        }
        // AppKit은 속성 문자열이 오면 markedTextAttributes 대신 입력기가 보낸 장식을 그린다.
        let marked = NSMutableAttributedString(attributedString: attributed)
        let range = NSRange(location: 0, length: marked.length)
        for key in [NSAttributedString.Key.underlineStyle, .underlineColor, .foregroundColor, .backgroundColor] {
            marked.removeAttribute(key, range: range)
        }
        marked.addAttributes(markedTextAttributes ?? [:], range: range)
        super.setMarkedText(marked, selectedRange: selectedRange, replacementRange: replacementRange)
    }

    open override func viewWillMove(toWindow newWindow: NSWindow?) {
        if let windowResignation { NotificationCenter.default.removeObserver(windowResignation) }
        windowResignation = nil
        super.viewWillMove(toWindow: newWindow)
        guard let newWindow else { return }
        windowResignation = NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification,
                                                                  object: newWindow, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                // 창이 키 창에서 물러나도 첫 응답자는 그대로일 수 있다.
                guard let self, self.window?.firstResponder === self else { return }
                self.commitComposition()
            }
        }
    }

    isolated deinit {
        if let windowResignation { NotificationCenter.default.removeObserver(windowResignation) }
    }

    open override func resignFirstResponder() -> Bool {
        commitComposition()
        return super.resignFirstResponder()
    }

    private func commitComposition() {
        guard hasMarkedText() else { return }
        let range = markedRange()
        let syllables = (string as NSString).substring(with: range)
        insertText(syllables, replacementRange: range)
        inputContext?.discardMarkedText()
    }
}
