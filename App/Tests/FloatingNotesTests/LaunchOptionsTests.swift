import Foundation
import Models
import Testing
@testable import FloatingNotes

@Suite struct LaunchOptionsTests {
    @Test func notesDirectoryAndAppearanceAreParsed() throws {
        let options = try LaunchOptions(arguments: ["app", "--notes-dir", "/tmp/notes", "--appearance", "dark", "-x"])
        #expect(options.notesDirectory?.path == "/tmp/notes")
        #expect(options.appearance == .dark)
        #expect(throws: LaunchOptions.ParseError.invalidAppearance("blue")) {
            try LaunchOptions(arguments: ["app", "--appearance", "blue"])
        }
        #expect(throws: LaunchOptions.ParseError.missingValue("--notes-dir")) {
            try LaunchOptions(arguments: ["app", "--notes-dir"])
        }
    }

    #if DEBUG
    /// 확인용 명령 통로는 출력 폴더를 함께 받아야 켜진다.
    @Test func debugControlNeedsAnOutputDirectory() throws {
        let options = try LaunchOptions(arguments: [
            "app", "--debug-control", "/tmp/out", "--debug-hover", "a", "--debug-hover", "b",
        ])
        #expect(options.debugControlDirectory?.path == "/tmp/out")
        #expect(options.debugHover == [NoteID(rawValue: "a"), NoteID(rawValue: "b")])
        #expect(try LaunchOptions(arguments: ["app"]).debugControlDirectory == nil)
        #expect(throws: LaunchOptions.ParseError.missingValue("--debug-control")) {
            try LaunchOptions(arguments: ["app", "--debug-control"])
        }
    }
    #endif
}
