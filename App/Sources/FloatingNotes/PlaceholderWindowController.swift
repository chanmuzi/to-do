import AppKit
import SwiftUI
import Theme

/// 임시 창 하나. 2단계에서 NotePanel의 노트 창이 이 자리를 대신한다
/// (`AppDelegate.showInitialWindows()`만 바꾸면 된다).
final class PlaceholderWindowController: NSWindowController {
    static let windowTitle = "FloatingNotes Placeholder"

    init(environment: AppEnvironment) throws {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 260),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = Self.windowTitle
        window.contentView = NSHostingView(
            rootView: PlaceholderView(
                theme: environment.theme,
                noteCount: try environment.notes.list().count,
                notesPath: environment.location.notesDirectory.path
            )
        )
        window.center()
        super.init(window: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("코드로만 만든다")
    }
}
