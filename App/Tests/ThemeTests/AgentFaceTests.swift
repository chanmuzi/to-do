import SwiftUI
import Testing
@testable import Theme

@MainActor @Suite struct AgentFaceTests {
    @Test func sizesAndStationaryGlyphs() throws {
        let theme = try Theme.bundled()
        #expect(AgentFaceSize.allCases.map { theme.component($0.token) } == [13, 14, 16, 20])
        #expect(AgentFaceSize.allCases.map(\.showsCorner) == [false, false, true, true])
        #expect(AgentFaceSize.allCases.map(\.showsProps) == [false, false, false, true])
        for state in AgentFaceState.allCases {
            for size in AgentFaceSize.allCases {
                let face = AgentFace(theme: theme, state: state, size: size).glyph(at: nil)
                    .frame(width: theme.component(size.token), height: theme.component(size.token))
                let image = try #require(ImageRenderer(content: face).cgImage)
                #expect(image.width == Int(theme.component(size.token)))
            }
        }
    }
}
