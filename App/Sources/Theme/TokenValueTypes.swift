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
    public let bell: BellMotion
    /// 짧은 알림(토스트)이 떠 있는 시간(초).
    public let toastHold: TimeInterval
}

/// 임박한 리마인더의 종이 흔들리는 움직임(spec 15).
public struct BellMotion: Hashable, Sendable {
    /// 한 주기(초).
    public let period: TimeInterval
    /// 주기의 앞부분에서 가만히 있는 몫(0~1). 남은 뒷부분에서만 흔들린다.
    public let rest: Double
    /// 차례로 기우는 각도(도). 마지막 각도 뒤에 0으로 돌아온다.
    public let angles: [Double]
    /// 돌리는 축의 자리. 아이콘 높이에서 위로부터의 몫(0~1).
    public let pivotFromTop: Double
    public let curve: BezierCurve

    /// 주기 안에서 각 자세가 놓이는 때(0~1)와 그때의 각도. 가만히 있다가 남은 시간을 고르게 나눠 기운다.
    public var keyframes: [(time: Double, degrees: Double)] {
        let step = (1 - rest) / Double(angles.count + 1)
        let swing = angles.enumerated().map { (time: rest + step * Double($0.offset + 1), degrees: $0.element) }
        return [(time: 0, degrees: 0), (time: rest, degrees: 0)] + swing + [(time: 1, degrees: 0)]
    }
}
