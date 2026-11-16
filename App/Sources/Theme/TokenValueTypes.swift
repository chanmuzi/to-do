import CoreGraphics
import Foundation

/// 그림자 한 겹(CSS box-shadow의 한 항목).
public struct ShadowLayer: Hashable, Sendable {
    public let x: CGFloat
    public let y: CGFloat
    public let blur: CGFloat
    public let spread: CGFloat
    public let color: RGBA
}

/// 네 변 여백.
public struct ThemeInsets: Hashable, Sendable {
    public let top: CGFloat
    public let trailing: CGFloat
    public let bottom: CGFloat
    public let leading: CGFloat
}

/// 팔레트 색 하나(노트 바탕, 스페이스 아이콘 색).
public struct PaletteColor: Hashable, Sendable, Identifiable {
    /// 팔레트 키(`tint-1` 등). 노트에는 이 키만 저장한다.
    public let id: String
    public let name: String
    public let color: RGBA
}

/// 강조색 프리셋.
public struct AccentPreset: Hashable, Sendable {
    public let name: String
    public let light: RGBA
    public let dark: RGBA
    public let onLight: RGBA
    public let onDark: RGBA
}

/// 재질 값.
public struct MaterialTokens: Hashable, Sendable {
    /// 창 불투명도(0~1).
    public let opacity: Double
    /// 배경 흐림 반경.
    public let blur: CGFloat
    /// 노트 바탕에 팔레트 색을 섞는 비율(0~1).
    public let tintMix: Double
    /// 목록 줄 바탕에 쓰는 팔레트 색의 알파(0~1).
    public let tintMixRow: Double
}

/// 3차 베지어 조절점.
public struct BezierCurve: Hashable, Sendable {
    public let x1: Double
    public let y1: Double
    public let x2: Double
    public let y2: Double
}

/// 움직임 값.
public struct MotionTokens: Hashable, Sendable {
    /// 전환 시간(초).
    public let duration: TimeInterval
    public let curve: BezierCurve
}
