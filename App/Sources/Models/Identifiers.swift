import Foundation

/// 노트 식별자. 노트 파일 이름(확장자 제외)과 같다.
public struct NoteID: RawRepresentable, Hashable, Codable, Sendable, CustomStringConvertible {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    /// 새 식별자를 만든다.
    public static func make() -> NoteID { NoteID(rawValue: UUID().uuidString.lowercased()) }
    public var description: String { rawValue }
}

/// 스페이스 식별자.
public struct SpaceID: RawRepresentable, Hashable, Codable, Sendable, CustomStringConvertible {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public static func make() -> SpaceID { SpaceID(rawValue: UUID().uuidString.lowercased()) }
    public var description: String { rawValue }
}

/// 팔레트 색 키(`tint-1` 등). 노트에는 색 값이 아니라 이 키만 저장한다(spec 3.3).
/// 실제 색은 `Theme`의 팔레트에서 찾는다.
public struct PaletteID: RawRepresentable, Hashable, Codable, Sendable, CustomStringConvertible {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public var description: String { rawValue }
}
