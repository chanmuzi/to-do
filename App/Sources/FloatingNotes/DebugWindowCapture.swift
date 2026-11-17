#if DEBUG
import AppKit

/// 확인용: 이 앱의 창 하나를 화면에서 그대로 찍는다(`screencapture -l <창 번호>`). 그 창만 찍고 화면 전체나
/// 다른 앱의 창은 찍지 않는다. 메뉴처럼 열려 있는 동안 돌아오지 않는 것은 열기 전에 시계를 걸어 둔다.
enum DebugWindowCapture {
    /// 그 창 하나를 찍어 `url`에 쓴다. 그림자도 함께 찍는다(테두리와 그림자의 가장자리를 보려고).
    static func capture(windowNumber: Int, to url: URL) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        process.arguments = ["-x", "-l\(windowNumber)", url.path]
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            AppLog.warning("창을 찍지 못했습니다(\(url.lastPathComponent)): \(error)")
        }
    }

    /// 화면의 그 사각형(그 창이 덮는 자리)만 찍는다. 메뉴 창은 시스템이 따로 그려 창 번호로 찍으면 비어 나온다.
    static func capture(frame: NSRect, to url: URL) {
        guard let primary = NSScreen.screens.first?.frame else { return }
        let rect = "\(Int(frame.minX)),\(Int(primary.maxY - frame.maxY)),\(Int(frame.width)),\(Int(frame.height))"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        process.arguments = ["-x", "-R\(rect)", url.path]
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            AppLog.warning("화면을 찍지 못했습니다(\(url.lastPathComponent)): \(error)")
        }
    }

    /// 메뉴를 열고(`open`은 메뉴가 닫힐 때까지 돌아오지 않는다) 잠시 뒤 새로 생긴 창(메뉴)이 덮는 자리만 찍은 뒤
    /// esc로 닫는다. 메뉴는 맨 위에 있으므로 그 자리에는 메뉴만 찍힌다(둥근 모서리 밖의 몇 점은 뒤가 보일 수 있다).
    static func captureMenu(to url: URL, open: () -> Void) {
        let known = Set(NSApplication.shared.windows.map(\.windowNumber))
        let timer = Timer(timeInterval: 0.8, repeats: false) { _ in
            MainActor.assumeIsolated {
                if let menu = NSApplication.shared.windows.first(where: {
                    !known.contains($0.windowNumber) && $0.isVisible
                }) {
                    capture(frame: menu.frame, to: url)
                } else {
                    AppLog.warning("열린 메뉴 창을 찾지 못했습니다")
                }
                guard let escape = NSEvent.keyEvent(
                    with: .keyDown, location: .zero, modifierFlags: [],
                    timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: 0, context: nil,
                    characters: "\u{1B}", charactersIgnoringModifiers: "\u{1B}", isARepeat: false, keyCode: 53
                ) else { return }
                NSApplication.shared.postEvent(escape, atStart: true)
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        open()
    }
}
#endif
