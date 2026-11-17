import Foundation
import Models
import Testing

@Suite struct SpaceIconCompatibilityTests {
    @Test func everyCaseCanBeReadByTheMainBuildAndRoundTrips() throws {
        let icons: [SpaceIcon] = [
            .symbol(name: "briefcase", colorID: PaletteID(rawValue: "tint-2")),
            .symbol(name: "star", colorID: nil),
            .customSymbol(name: "heart", hex: "#125678"),
            .emoji("🏠"), .image("custom.gif"), .none,
        ]
        let spaces = icons.enumerated().map { index, icon in
            Space(id: SpaceID(rawValue: "space-\(index)"), name: "공간 \(index)", icon: icon)
        }
        let data = try JSONEncoder().encode(spaces)
        let legacy = try JSONDecoder().decode([MainFormat.Space].self, from: data)
        #expect(legacy.map(\.id) == spaces.map(\.id))
        #expect(legacy.map(\.name) == spaces.map(\.name))
        #expect(legacy.map(\.icon) == [
            .symbol(name: "briefcase", colorID: PaletteID(rawValue: "tint-2")),
            .symbol(name: "star", colorID: nil),
            .symbol(name: "heart", colorID: nil),
            .emoji("🏠"), .image("custom.gif"), .emoji(""),
        ])
        #expect(try JSONDecoder().decode([Space].self, from: data) == spaces)
    }

    @Test func initialStageFiveCasesRemainReadableAndAreRewrittenCompatibly() throws {
        let data = Data(##"[{"id":"none","name":"없음","icon":{"none":{}}},{"id":"custom","name":"직접","icon":{"customSymbol":{"name":"star","hex":"#125678"}}}]"##.utf8)
        let spaces = try JSONDecoder().decode([Space].self, from: data)
        #expect(spaces.map(\.icon) == [.none, .customSymbol(name: "star", hex: "#125678")])
        let rewritten = try JSONEncoder().encode(spaces)
        #expect(try JSONDecoder().decode([MainFormat.Space].self, from: rewritten).map(\.icon)
            == [.emoji(""), .symbol(name: "star", colorID: nil)])
        #expect(try JSONDecoder().decode([Space].self, from: rewritten) == spaces)
    }

    @Test func malformedPayloadStillThrows() {
        for json in [#"{}"#, #"{"symbol":{"name":42}}"#, #"{"customSymbol":{"name":"star"}}"#] {
            #expect(throws: DecodingError.self) {
                try JSONDecoder().decode(SpaceIcon.self, from: Data(json.utf8))
            }
        }
    }
}

// git show main:App/Sources/Models/Space.swift의 정의를 그대로 옮겼다.
// 현재 모델과 이름이 겹치지 않도록 네임스페이스만 감싼다. 합성 Codable을 유지한다.
private enum MainFormat {
    /// 스페이스(노트 묶음). 예: 회사, 개인.
    public struct Space: Identifiable, Hashable, Codable, Sendable {
        public let id: SpaceID
        public var name: String
        public var icon: SpaceIcon

        public init(id: SpaceID, name: String, icon: SpaceIcon) {
            self.id = id
            self.name = name
            self.icon = icon
        }
    }

    /// 스페이스 아이콘. 아이콘 고르기의 세 탭(기호, 이모지, 이미지)에 대응한다(spec 10).
    /// 세부는 Library 단계에서 spec 10에 맞춰 다듬는다(임시 형태).
    public enum SpaceIcon: Hashable, Codable, Sendable {
        /// SF Symbols 이름과 색. 색은 팔레트 키이고 `nil`이면 글자색.
        case symbol(name: String, colorID: PaletteID?)
        case emoji(String)
        /// 기본 이미지 id(`terminal` 등) 또는 사용자가 올린 이미지 파일 이름.
        case image(String)
    }
}
