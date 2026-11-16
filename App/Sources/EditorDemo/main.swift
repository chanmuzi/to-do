import AppKit
@_spi(Verification) import Editor
import Theme

// 편집기만 노트 너비의 창 하나에 띄운다. 화면 2와 견주어 보는 데 쓴다.
// 창 번호를 표준 출력에 적으므로 그 창만 캡처할 수 있다: `screencapture -l <번호> out.png`

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("\(message)\n".utf8))
    exit(64)
}

/// 테두리 없는 창도 키 창이 될 수 있게 한다(`--activate`일 때만 키 창으로 만든다).
final class DemoWindow: NSPanel {
    override var canBecomeKey: Bool { true }
}

/// 노트 바탕(`surface`)을 칠하는 뷰. 편집기는 바탕을 그리지 않는다.
final class BackgroundView: NSView {
    private let color: NSColor

    init(color: NSColor) {
        self.color = color
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draw(_ dirtyRect: NSRect) {
        color.setFill()
        bounds.fill()
    }
}

final class DemoDelegate: NSObject, NSApplicationDelegate {
    private let options: DemoOptions
    private var theme: Theme?
    private var editor: MarkdownEditor?
    private var window: DemoWindow?

    init(options: DemoOptions) {
        self.options = options
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard let sample = DemoSamples.text(named: options.sample) else { fail("모르는 --sample: \(options.sample)") }
        let registration = FontRegistrar.registerBundledFonts()
        registration.problems.forEach { FileHandle.standardError.write(Data("글꼴: \($0)\n".utf8)) }
        NSApp.appearance = options.appearance.nsAppearance

        let theme: Theme
        do {
            theme = try Theme.bundled(appearance: options.appearance)
        } catch {
            fail("테마를 읽지 못했습니다: \(error)")
        }
        let editor = MarkdownEditor(theme: theme, configuration: MarkdownEditorConfiguration(checkboxStyle: options.checkboxStyle))
        self.theme = theme
        self.editor = editor

        let width = CGFloat(options.width)
        let window = DemoWindow(
            contentRect: NSRect(x: 0, y: 0, width: width, height: 100),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        window.backgroundColor = theme.nsColor(.surface)
        window.hasShadow = true
        window.isReleasedWhenClosed = false
        window.hidesOnDeactivate = false
        let background = BackgroundView(color: theme.nsColor(.surface))
        editor.view.frame = background.bounds
        editor.view.autoresizingMask = [.width, .height]
        background.addSubview(editor.view)
        window.contentView = background
        self.window = window

        editor.onContentHeightChange = { [weak self] height in self?.resize(to: height) }
        editor.text = sample
        editor.foldedLines = options.folded
        editor.forcesActiveAppearance = !options.activates
        resize(to: editor.contentHeight)

        if options.activates {
            window.makeKeyAndOrderFront(nil)
        } else {
            window.orderFrontRegardless()
        }
        if options.caretLine != nil || !options.script.isEmpty {
            editor.focus()
            if let line = options.caretLine { DemoScript.placeCaret(atEndOfLine: line, in: editor) }
        }
        DemoScript.run(options.script, on: editor).forEach { FileHandle.standardError.write(Data("\($0)\n".utf8)) }
        resize(to: editor.contentHeight)

        var output = "WINDOW \(window.windowNumber)\n"
        if options.printsText { output += "TEXT-BEGIN\n\(editor.text)\nTEXT-END\n" }
        output += "SELECTION \(editor.selectedRange.location) \(editor.selectedRange.length)\n"
        output += "FOLDED \(editor.foldedLines.sorted().map(String.init).joined(separator: ","))\n"
        FileHandle.standardOutput.write(Data(output.utf8))

        if let path = options.snapshotPath {
            // 그리기가 한 번 끝난 뒤에 찍는다.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
                self?.reportCaret()
                self?.writeSnapshot(to: path)
                NSApp.terminate(nil)
            }
        }
    }

    /// 입력 커서(시스템이 그리는 뷰)의 크기와 색을 적는다. 창이 키 창일 때만 있다.
    private func reportCaret() {
        guard let editor else { return }
        func find(_ view: NSView) -> NSTextInsertionIndicator? {
            if let indicator = view as? NSTextInsertionIndicator { return indicator }
            return view.subviews.lazy.compactMap(find).first
        }
        guard let indicator = find(editor.textView) else {
            FileHandle.standardOutput.write(Data("CARET none\n".utf8))
            return
        }
        let line = "CARET width=\(indicator.frame.width) height=\(indicator.frame.height) color=\(String(describing: indicator.color)) mode=\(indicator.displayMode.rawValue)\n"
        FileHandle.standardOutput.write(Data(line.utf8))
    }

    /// 창의 내용을 이 프로세스 안에서 PNG로 그려 낸다(화면 녹화 권한이 필요 없고 다른 창이 찍히지 않는다).
    private func writeSnapshot(to path: String) {
        guard let view = window?.contentView, let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
            fail("창 내용을 그리지 못했습니다")
        }
        view.cacheDisplay(in: view.bounds, to: bitmap)
        guard let data = bitmap.representation(using: .png, properties: [:]) else { fail("PNG로 바꾸지 못했습니다") }
        do {
            try data.write(to: URL(fileURLWithPath: path))
        } catch {
            fail("캡처를 쓰지 못했습니다: \(error)")
        }
    }

    /// 창의 위쪽 가장자리를 고정하고 아래로 늘린다.
    private func resize(to height: CGFloat) {
        guard let window, let screen = NSScreen.main else { return }
        let top = screen.frame.maxY - CGFloat(options.origin.y)
        window.setFrame(
            NSRect(x: screen.frame.minX + CGFloat(options.origin.x), y: top - height, width: CGFloat(options.width), height: height),
            display: true
        )
    }
}

let options: DemoOptions
do {
    options = try DemoOptions(arguments: CommandLine.arguments)
} catch {
    fail("\(error)")
}

let application = NSApplication.shared
let delegate = DemoDelegate(options: options)
application.delegate = delegate
// Dock에 나타나지 않고 다른 앱의 포커스를 빼앗지 않는다.
application.setActivationPolicy(.accessory)
application.run()
