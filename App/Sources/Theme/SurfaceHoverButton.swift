import SwiftUI

/// 이미 그려진 버튼 면 위에 같은 모양으로 호버 색만 겹친다.
package struct SurfaceHoverButton<S: Shape>: ButtonStyle {
    let theme: Theme
    let shape: S
    @Environment(\.accessibilityReduceMotion) private var reduced
    @Environment(\.isEnabled) private var enabled
    @State private var hovered = false

    package init(_ theme: Theme, shape: S) {
        self.theme = theme
        self.shape = shape
    }

    package func makeBody(configuration: Configuration) -> some View {
        let active = enabled && (hovered || configuration.isPressed || theme.previewsSurfaceHover)
        configuration.label
            .overlay { shape.fill(active ? theme.color(.hover) : .clear).allowsHitTesting(false) }
            .contentShape(shape)
            .onHover { hovered = $0 }
            .animation(reduced ? nil : theme.motion.animation, value: active)
    }
}

extension Theme {
    var previewsSurfaceHover: Bool {
        #if DEBUG
        verificationSurfaceHover
        #else
        false
        #endif
    }
}
