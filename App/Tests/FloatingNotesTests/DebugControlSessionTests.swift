#if DEBUG
import AppKit
import Testing
@testable import FloatingNotes

/// 확인용 명령 통로: 명령마다 이번 실행의 표가 있어야 하고, 출력은 받은 폴더 밖으로 나가지 못한다.
@Suite struct DebugControlSessionTests {
    private let directory = URL(fileURLWithPath: ProcessInfo.processInfo.environment["TMPDIR"] ?? NSTemporaryDirectory(), isDirectory: true)
        .appendingPathComponent("debug-control-tests-\(UUID().uuidString)", isDirectory: true)

    private func cleanUp() {
        try? FileManager.default.removeItem(at: directory)
    }

    @Test func sidebarEndScrollsAPlainDocumentWithoutResponderCommands() {
        final class Flipped: NSView { override var isFlipped: Bool { true } }
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 180, height: 100))
        let document = Flipped(frame: NSRect(x: 0, y: 0, width: 180, height: 500))
        scroll.documentView = document
        DebugLibraryInput.scrollToEnd(scroll)
        #expect(scroll.documentVisibleRect.maxY == document.bounds.maxY)
    }

    @Test func eachLaunchWritesAFreshOwnerOnlyToken() throws {
        defer { cleanUp() }
        let first = try DebugControlSession.start(in: directory)
        let tokenFile = directory.appendingPathComponent("control-token")
        #expect(try String(contentsOf: tokenFile, encoding: .utf8) == first.token)
        let permissions = try FileManager.default.attributesOfItem(atPath: tokenFile.path)[.posixPermissions]
        #expect((permissions as? NSNumber)?.intValue == 0o600)

        let second = try DebugControlSession.start(in: directory)
        #expect(second.token != first.token)
        #expect(try String(contentsOf: tokenFile, encoding: .utf8) == second.token)
        // 지난 실행의 표로는 명령이 통하지 않는다.
        #expect(second.command(from: "\(first.token) quit") == nil)
    }

    @Test func commandsWithoutTheTokenAreDropped() throws {
        defer { cleanUp() }
        let session = try DebugControlSession.start(in: directory)
        #expect(session.command(from: "\(session.token) dump state.json") == "dump state.json")
        #expect(session.command(from: "quit") == nil)
        #expect(session.command(from: "trash some-note") == nil)
        #expect(session.command(from: "wrong-token quit") == nil)
        #expect(session.command(from: session.token) == nil)
        #expect(session.command(from: "\(session.token) ") == nil)
        #expect(session.command(from: " \(session.token) quit") == nil)
        #expect(session.command(from: "") == nil)
    }

    @Test func outputsStayInsideTheLaunchDirectory() throws {
        defer { cleanUp() }
        let session = try DebugControlSession.start(in: directory)
        #expect(session.outputURL(named: "state.json")?.path
            == directory.standardizedFileURL.appendingPathComponent("state.json").path)
        for name in [
            "", "/etc/hosts", "../escape.png", "sub/file.png", "..", ".", ".zshrc",
            "\(NSHomeDirectory())/.zshrc", "control-token",
        ] {
            #expect(session.outputURL(named: name) == nil, "\(name)")
        }
        // 폴더 안에 놓인 링크를 따라 밖에 쓰지 않는다.
        let outside = URL(fileURLWithPath: ProcessInfo.processInfo.environment["TMPDIR"] ?? NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("debug-control-outside-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: outside) }
        try FileManager.default.createSymbolicLink(
            at: directory.appendingPathComponent("link.png"), withDestinationURL: outside
        )
        #expect(session.outputURL(named: "link.png") == nil)
    }
}
#endif
