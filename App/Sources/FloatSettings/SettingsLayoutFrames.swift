import SwiftUI

#if DEBUG
/// 위쪽 왼쪽을 원점으로 하는 설정 창 안의 배치 좌표.
struct SettingsLayoutFrames: PreferenceKey {
    static let defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}
#endif

extension View {
    @ViewBuilder func settingsMeasure(_ name: String) -> some View {
        #if DEBUG
        background {
            GeometryReader { geometry in
                Color.clear.preference(key: SettingsLayoutFrames.self, value: [name: geometry.frame(in: .named("settingsLayout"))])
            }.allowsHitTesting(false).accessibilityHidden(true)
        }
        #else
        self
        #endif
    }
}
