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
