#if DEBUG
import AppKit
@_spi(Verification) import Browse
@_spi(Verification) import Capture

extension QuickPanels {
    /// `--debug-passive`: 캡처 바와 노트 찾기가 키 창이 되지 않게 한다(확인용 실행이 사용자의 키 입력을 가져오지 않게).
    /// 글자와 키는 확인용 명령 `panel …`로 넣는다.
    func refuseKeyWindowsForVerification() {
        capture.takesKeyOnShow = false
        browse.takesKeyOnShow = false
    }
}

/// 떠 있는 캡처 바와 노트 찾기에 확인용 명령으로 글자와 키를 넣고 상태를 읽는 곳. 디버그 빌드에만 있다.
/// 실제 입력 경로(`insertText`, `doCommand(by:)`)를 부르고 시스템에 키 이벤트를 보내지 않는다.
///
/// - `panel capture|browse type <글자>`: 입력 칸에 글자를 넣는다.
/// - `panel capture key return|esc|tab|cmd-return`, `panel browse key return|esc|up|down`
/// - `panel screen <번호>`: 붙이지 않고 띄울 때 쓸 화면을 정한다(`NSScreen.screens`의 차례).
final class DebugQuickPanels {
    private let panels: QuickPanels

    init(panels: QuickPanels) {
        self.panels = panels
    }

    /// - Parameter words: `panel` 뒤의 낱말들. 둘째 낱말은 나머지 줄 전체다(`type <글자>`).
    /// - Returns: 아는 명령이었는지.
    func run(_ words: [String]) -> Bool {
        guard let target = words.first, words.count > 1 else { return false }
        let rest = words[1].split(separator: " ", maxSplits: 1).map(String.init)
        if target == "screen" {
            guard let index = Int(words[1]), NSScreen.screens.indices.contains(index) else { return false }
            panels.capture.preferredScreen = NSScreen.screens[index]
            panels.browse.preferredScreen = NSScreen.screens[index]
            return true
        }
        guard let input = target == "capture" ? panels.capture.inputView : panels.browse.inputView,
              target == "capture" || target == "browse", let verb = rest.first
        else { return false }
        switch (verb, rest.dropFirst().first) {
        case ("input-focus", let state?):
            guard let window = window(named: target), !window.isKeyWindow else { return false }
            if state == "off" { window.makeFirstResponder(nil) }
            else if state == "on", let root = window.contentView {
                func field(in view: NSView) -> NSTextField? {
                    if let field = view as? NSTextField, field.isEditable { return field }
                    return view.subviews.lazy.compactMap { field(in: $0) }.first
                }
                window.makeFirstResponder(field(in: root))
            } else { return false }
        case ("type", let text?):
            input.insertText(text, replacementRange: NSRange(location: NSNotFound, length: 0))
        case ("key", "cmd-return"?) where target == "capture":
            panels.capture.performSubmitAsNewNote()
        case ("key", let name?):
            guard let selector = Self.selectors[name] else { return false }
            input.doCommand(by: selector)
        default:
            return false
        }
        return true
    }

    func input(named target: String) -> NSTextView? {
        target == "capture" ? panels.capture.inputView : target == "browse" ? panels.browse.inputView : nil
    }

    /// `capture` 또는 `browse`의 창. 한 번도 띄우지 않았으면 `nil`.
    func window(named target: String) -> NSWindow? {
        switch target {
        case "capture": panels.capture.window
        case "browse": panels.browse.window
        default: nil
        }
    }

    private static let selectors: [String: Selector] = [
        "return": #selector(NSResponder.insertNewline(_:)),
        "esc": #selector(NSResponder.cancelOperation(_:)),
        "tab": #selector(NSResponder.insertTab(_:)),
        "up": #selector(NSResponder.moveUp(_:)),
        "down": #selector(NSResponder.moveDown(_:)),
    ]

    /// `dump`에 넣는 두 화면의 상태.
    func dump() -> [String: Any] {
        func frame(_ rect: NSRect) -> [CGFloat] { [rect.minX, rect.minY, rect.width, rect.height] }
        return [
            "capture": [
                "visible": panels.capture.isVisible,
                "key": panels.capture.window?.isKeyWindow ?? false,
                "windowNumber": panels.capture.window?.windowNumber ?? 0,
                "frame": frame(panels.capture.settledFrame),
                "text": panels.capture.inputView?.string ?? "",
                "space": panels.capture.displayedSpace ?? "",
                "reminder": panels.capture.displayedReminder ?? "",
            ] as [String: Any],
            "browse": [
                "visible": panels.browse.isVisible,
                "key": panels.browse.window?.isKeyWindow ?? false,
                "windowNumber": panels.browse.window?.windowNumber ?? 0,
                "frame": frame(panels.browse.window?.frame ?? .zero),
                "text": panels.browse.inputView?.string ?? "",
                "rows": panels.browse.rowDescriptions,
            ] as [String: Any],
        ]
    }
}
#endif
