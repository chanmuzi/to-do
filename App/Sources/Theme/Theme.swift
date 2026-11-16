import AppKit
import Observation

/// 앱이 쓰는 테마. 토큰(+사용자 덮어쓰기)과 지금의 라이트·다크를 들고 있다.
///
/// - SwiftUI 뷰는 이 객체를 읽기만 하면 덮어쓰기나 모양이 바뀔 때 다시 그려진다(`@Observable`).
/// - AppKit 코드는 `Theme.didChangeNotification`을 받는다.
/// - `nsColor(_:)`, `color(_:)`가 주는 색은 뷰의 라이트·다크를 스스로 따라간다.
@MainActor
@Observable
public final class Theme {
    /// 덮어쓰기나 라이트·다크가 바뀐 뒤에 보낸다. `object`는 이 테마.
    public static let didChangeNotification = Notification.Name("FloatingNotes.Theme.didChange")

    /// 덮어쓰기를 얹은 지금의 토큰.
    public private(set) var tokens: ThemeTokens
    public private(set) var overrides: ThemeOverrides
    /// 지금의 라이트·다크. `followAppearance(of:)`를 부른 뒤로는 앱 모양을 따라간다.
    public private(set) var appearance: ThemeAppearance

    @ObservationIgnored private let baseTokens: ThemeTokens
    @ObservationIgnored private let overrideStore: ThemeOverrideStore?
    @ObservationIgnored private var appearanceObservation: NSKeyValueObservation?

    /// - Parameters:
    ///   - baseTokens: `tokens.json`에서 읽은 값.
    ///   - overrideStore: 덮어쓰기를 저장할 곳. 있으면 저장된 값을 읽어 얹고, 바꿀 때마다 저장한다.
    public init(
        baseTokens: ThemeTokens,
        overrideStore: ThemeOverrideStore? = nil,
        appearance: ThemeAppearance = .light
    ) throws {
        let overrides = try overrideStore?.load() ?? ThemeOverrides()
        self.baseTokens = baseTokens
        self.overrideStore = overrideStore
        self.overrides = overrides
        self.tokens = try baseTokens.applying(overrides)
        self.appearance = appearance
    }

    /// 번들의 `tokens.json`으로 만든다.
    public static func bundled(
        overrideStore: ThemeOverrideStore? = nil,
        appearance: ThemeAppearance = .light
    ) throws -> Theme {
        try Theme(baseTokens: .bundled(), overrideStore: overrideStore, appearance: appearance)
    }

    /// 덮어쓰기를 통째로 바꾼다. 값이 잘못됐으면 던지고 아무것도 바꾸지 않는다.
    public func setOverrides(_ newOverrides: ThemeOverrides) throws {
        let newTokens = try baseTokens.applying(newOverrides)
        try overrideStore?.save(newOverrides)
        overrides = newOverrides
        tokens = newTokens
        notifyChange()
    }

    /// 앱의 모양(시스템 설정 또는 `NSApp.appearance`)을 따라가기 시작한다.
    public func followAppearance(of application: NSApplication) {
        setAppearance(ThemeAppearance(application.effectiveAppearance))
        appearanceObservation = application.observe(\.effectiveAppearance) { [weak self] application, _ in
            MainActor.assumeIsolated {
                self?.setAppearance(ThemeAppearance(application.effectiveAppearance))
            }
        }
    }

    private func setAppearance(_ newAppearance: ThemeAppearance) {
        guard newAppearance != appearance else { return }
        appearance = newAppearance
        notifyChange()
    }

    private func notifyChange() {
        NotificationCenter.default.post(name: Self.didChangeNotification, object: self)
    }
}
