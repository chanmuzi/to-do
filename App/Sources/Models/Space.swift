import Foundation

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
/// 옛 빌드도 읽을 수 있는 symbol/emoji/image 형식으로 저장한다(D-050).
public enum SpaceIcon: Hashable, Codable, Sendable {
    /// SF Symbols 이름과 색. 색은 팔레트 키이고 `nil`이면 글자색.
    case symbol(name: String, colorID: PaletteID?)
    /// 직접 고른 sRGB 색(#RRGGBB). symbol payload의 hex로 저장한다.
    case customSymbol(name: String, hex: String)
    case none
    case emoji(String)
    /// 기본 이미지 id(`terminal` 등) 또는 사용자가 올린 이미지 파일 이름.
    case image(String)

    private enum CodingKeys: String, CodingKey {
        case symbol, emoji, image, none, customSymbol
    }
    private enum PayloadKeys: String, CodingKey {
        case name, colorID, hex, _0
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard container.allKeys.count == 1, let key = container.allKeys.first else {
            throw DecodingError.dataCorrupted(.init(
                codingPath: decoder.codingPath, debugDescription: "아이콘 종류는 하나여야 합니다."
            ))
        }
        let payload = try container.nestedContainer(keyedBy: PayloadKeys.self, forKey: key)
        switch key {
        case .symbol:
            let name = try payload.decode(String.self, forKey: .name)
            if let hex = try payload.decodeIfPresent(String.self, forKey: .hex) {
                self = .customSymbol(name: name, hex: hex)
            } else {
                self = .symbol(name: name, colorID: try payload.decodeIfPresent(PaletteID.self, forKey: .colorID))
            }
        case .emoji:
            let emoji = try payload.decode(String.self, forKey: ._0)
            self = emoji.isEmpty ? .none : .emoji(emoji)
        case .image:
            self = .image(try payload.decode(String.self, forKey: ._0))
        // 이 브랜치의 초기 빌드가 합성 Codable로 쓴 파일도 읽는다.
        case .none:
            self = .none
        case .customSymbol:
            self = .customSymbol(name: try payload.decode(String.self, forKey: .name),
                                 hex: try payload.decode(String.self, forKey: .hex))
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .symbol(let name, let colorID):
            var payload = container.nestedContainer(keyedBy: PayloadKeys.self, forKey: .symbol)
            try payload.encode(name, forKey: .name)
            try payload.encodeIfPresent(colorID, forKey: .colorID)
        case .customSymbol(let name, let hex):
            var payload = container.nestedContainer(keyedBy: PayloadKeys.self, forKey: .symbol)
            try payload.encode(name, forKey: .name)
            try payload.encodeNil(forKey: .colorID)
            try payload.encode(hex, forKey: .hex)
        case .none, .emoji:
            var payload = container.nestedContainer(keyedBy: PayloadKeys.self, forKey: .emoji)
            let value = if case .emoji(let emoji) = self { emoji } else { "" }
            try payload.encode(value, forKey: ._0)
        case .image(let image):
            var payload = container.nestedContainer(keyedBy: PayloadKeys.self, forKey: .image)
            try payload.encode(image, forKey: ._0)
        }
    }
}
