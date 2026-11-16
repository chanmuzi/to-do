import AppKit
@_spi(Verification) import Browse
@_spi(Verification) import Capture
import Models

/// `--script`의 단계를 차례로 실행한다. 실제 입력 경로(`insertText`, `setMarkedText`, `doCommand(by:)`)를 부르고,
/// 시스템에 키나 마우스 이벤트를 보내지 않는다.
///
/// 단계:
/// - `show:capture` | `show:browse` | `show:browse-anchored` | `show:browse-anchored-excluding:<노트 id>` | `hide`
/// - `type:<글>`: 글자 입력. `mark:<글>`: 조합 중인 글자로 넣는다(한글 입력기 흉내). `unmark`: 조합을 끝낸다
/// - `return` | `tab` | `backtab` | `esc` | `up` | `down` | `backspace`
/// - `cmd-return` | `cmd-r`: 캡처 바의 ⌘↵, ⌘R
/// - `wait:<밀리초>`, `dump`: 지금 상태를 표준 출력에 적는다, `snapshot:<경로>`: 지금 창을 PNG로 그려 낸다
/// - `screencap:<경로>`: 지금 창 하나만 화면에서 찍는다(그림자, 뒤 배경 흐림 포함. 화면이 잠겨 있으면 안 된다)
@MainActor
final class DemoScript {
    private let capture: CaptureCoordinator
    private let browse: BrowseCoordinator
    private let anchor: NSWindow
    private let wall: NSColor
    private let output: (String) -> Void
    /// 마지막으로 띄운 것. 입력 단계가 여기로 간다.
    private(set) var target: Target = .capture

    enum Target {
        case capture, browse
    }

    init(
        capture: CaptureCoordinator, browse: BrowseCoordinator, anchor: NSWindow, wall: NSColor,
        output: @escaping (String) -> Void
    ) {
        self.capture = capture
        self.browse = browse
        self.anchor = anchor
        self.wall = wall
        self.output = output
    }

    var window: NSWindow? { target == .capture ? capture.window : browse.window }
    private var inputView: NSTextView? { target == .capture ? capture.inputView : browse.inputView }

    func run(_ steps: [String]) async {
        for step in steps where !step.isEmpty {
            await run(step)
            // 다음 단계 전에 메인 큐를 한 번 돌려 배치와 알림이 지나가게 한다.
            try? await Task.sleep(for: .milliseconds(30))
        }
    }

    private func run(_ step: String) async {
        let parts = step.split(separator: ":", maxSplits: 1).map(String.init)
        let name = parts[0]
        let argument = parts.count > 1 ? parts[1] : ""
        switch name {
        case "show": show(argument)
        case "hide": target == .capture ? capture.hide() : browse.hide()
        case "type": inputView?.insertText(argument, replacementRange: NSRange(location: NSNotFound, length: 0))
        case "mark":
            inputView?.setMarkedText(
                argument, selectedRange: NSRange(location: (argument as NSString).length, length: 0),
                replacementRange: NSRange(location: NSNotFound, length: 0)
            )
        case "unmark": inputView?.unmarkText()
        case "return": command(#selector(NSResponder.insertNewline(_:)))
        case "tab": command(#selector(NSResponder.insertTab(_:)))
        case "backtab": command(#selector(NSResponder.insertBacktab(_:)))
        case "esc": command(#selector(NSResponder.cancelOperation(_:)))
        case "up": command(#selector(NSResponder.moveUp(_:)))
        case "down": command(#selector(NSResponder.moveDown(_:)))
        case "backspace": command(#selector(NSResponder.deleteBackward(_:)))
        case "cmd-return": capture.performSubmitAsNewNote()
        case "cmd-r": capture.performCycleReminder()
        case "wait": try? await Task.sleep(for: .milliseconds(Int(argument) ?? 0))
        case "dump": dump()
        case "snapshot": snapshot(to: argument)
        case "screencap": screenCapture(to: argument)
        default: output("SCRIPT 모르는 단계: \(step)")
        }
    }

    private func command(_ selector: Selector) {
        inputView?.doCommand(by: selector)
    }

    private func show(_ what: String) {
        switch what {
        case "capture":
            target = .capture
            capture.show()
        case "browse":
            target = .browse
            browse.show(anchoredTo: nil, excluding: nil)
        case "browse-anchored":
            target = .browse
            anchor.orderFrontRegardless()
            browse.show(anchoredTo: anchor, excluding: nil)
        case let value where value.hasPrefix("browse-anchored-excluding:"):
            target = .browse
            anchor.orderFrontRegardless()
            browse.show(
                anchoredTo: anchor,
                excluding: NoteID(rawValue: String(value.dropFirst("browse-anchored-excluding:".count)))
            )
        default:
            output("SCRIPT 모르는 show: \(what)")
        }
        if let window { output("WINDOW \(window.windowNumber)") }
    }

    func dump() {
        switch target {
        case .capture:
            let underline = capture.underlinedRange.map { "\($0.location)+\($0.length)" } ?? "-"
            output("CAPTURE visible=\(capture.isVisible) key=\(capture.window?.isKeyWindow ?? false) text=\"\(capture.inputView?.string ?? "")\""
                + " marked=\(capture.inputView?.hasMarkedText() ?? false)"
                + " space=\(capture.displayedSpace ?? "-") reminder=\(capture.displayedReminder ?? "-")"
                + " underline=\(underline) placeholder=\(capture.showsPlaceholder)"
                + " frame=\(capture.window.map { NSStringFromRect($0.frame) } ?? "-")")
        case .browse:
            output("BROWSE visible=\(browse.isVisible) key=\(browse.window?.isKeyWindow ?? false) text=\"\(browse.inputView?.string ?? "")\""
                + " marked=\(browse.inputView?.hasMarkedText() ?? false) placeholder=\(browse.showsPlaceholder)"
                + " frame=\(browse.window.map { NSStringFromRect($0.frame) } ?? "-")"
                + " settled=\(NSStringFromRect(browse.settledFrame))")
            browse.rowDescriptions.forEach { output("  ROW \($0)") }
        }
    }

    /// 지금 창 하나만 화면에서 찍는다(`screencapture -l <창 번호>`). 그림자와 뒤 배경 흐림까지 찍힌다.
    /// 화면 전체는 찍지 않는다. 화면이 잠겨 있으면 실패한다.
    private func screenCapture(to path: String) {
        guard let window else {
            output("SCREENCAP 창이 없습니다")
            return
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        process.arguments = ["-x", "-l", String(window.windowNumber), path]
        do {
            try process.run()
            process.waitUntilExit()
            output("SCREENCAP \(path) exit=\(process.terminationStatus)")
        } catch {
            output("SCREENCAP 실패: \(error)")
        }
    }

    func snapshot(to path: String) {
        guard let window else {
            output("SNAPSHOT 창이 없습니다")
            return
        }
        do {
            try DemoSnapshot.write(window: window, wall: wall, to: path)
            output("SNAPSHOT \(path)")
        } catch {
            output("SNAPSHOT 실패: \(error)")
        }
    }
}
