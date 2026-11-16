import Foundation
import Testing
import Models

@Suite struct ModelsTests {
    @Test func noteIDsAreUnique() {
        #expect(NoteID.make() != NoteID.make())
    }

    @Test func newWindowStateIsPinnedAndClosed() {
        let state = NoteWindowState()
        #expect(state.isPinned)
        #expect(!state.isOpen)
        #expect(state.frame == nil)
    }

    /// 접힌 줄은 나중에 더한 항목이다. 그 항목이 없는 예전 상태 파일도 읽히고, 있으면 그대로 오간다.
    @Test func windowStateReadsOlderFilesWithoutFoldedLines() throws {
        let older = Data(#"{"isPinned":false,"isOpen":true,"stackOrder":3}"#.utf8)
        let decoded = try JSONDecoder().decode(NoteWindowState.self, from: older)
        #expect(decoded == NoteWindowState(isPinned: false, isOpen: true, stackOrder: 3))
        #expect(decoded.foldedLines == nil)

        let folded = NoteWindowState(isOpen: true, foldedLines: [1, 4])
        let roundTripped = try JSONDecoder().decode(NoteWindowState.self, from: JSONEncoder().encode(folded))
        #expect(roundTripped == folded)
    }

    @Test func windowFrameConvertsToAndFromCGRect() {
        let rect = CGRect(x: 10, y: 20, width: 340, height: 200)
        #expect(WindowFrame(rect).cgRect == rect)
    }

    @Test func spaceRoundTripsThroughJSON() throws {
        let spaces = [
            Space(id: SpaceID(rawValue: "work"), name: "회사",
                  icon: .symbol(name: "briefcase", colorID: PaletteID(rawValue: "tint-2"))),
            Space(id: SpaceID(rawValue: "home"), name: "개인", icon: .emoji("🏠")),
        ]
        let data = try JSONEncoder().encode(spaces)
        #expect(try JSONDecoder().decode([Space].self, from: data) == spaces)
    }
}
