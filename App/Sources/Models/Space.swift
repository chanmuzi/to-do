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
/// 세부는 Library 단계에서 spec 10에 맞춰 다듬는다(임시 형태).
public enum SpaceIcon: Hashable, Codable, Sendable {
    /// SF Symbols 이름과 색. 색은 팔레트 키이고 `nil`이면 글자색.
    case symbol(name: String, colorID: PaletteID?)
    case emoji(String)
    /// 기본 이미지 id(`terminal` 등) 또는 사용자가 올린 이미지 파일 이름.
    case image(String)
}
