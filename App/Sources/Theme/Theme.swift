import AppKit
import Observation

/// 앱이 쓰는 테마. 토큰(+사용자 덮어쓰기)과 지금의 라이트, 다크를 들고 있다.
///
/// - SwiftUI 뷰는 이 객체를 읽기만 하면 덮어쓰기나 모양이 바뀔 때 다시 그려진다(`@Observable`).
/// - AppKit 코드는 `Theme.didChangeNotification`을 받는다.
/// - `nsColor(_:)`, `color(_:)`가 주는 색은 뷰의 라이트, 다크를 스스로 따라간다.
@MainActor
@Observable
public final class Theme {
    #if DEBUG
    package var verificationSurfaceHover = false
    #endif

    /// 덮어쓰기나 라이트, 다크가 바뀐 뒤에 보낸다. `object`는 이 테마.
    public static let didChangeNotification = Notification.Name("FloatingNotes.Theme.didChange")

    /// 덮어쓰기를 얹은 지금의 토큰.
    public private(set) var tokens: ThemeTokens
    public private(set) var overrides: ThemeOverrides
    /// 지금의 라이트, 다크. `followAppearance(of:)`를 부른 뒤로는 앱 모양을 따라간다.
    public private(set) var appearance: ThemeAppearance

    /// 저장된 덮어쓰기를 읽으면서 버린 것(없어진 키, 잘못된 값, 망가진 파일)의 설명.
    /// 앱이 켤 때 모아서 기록한다. 문제가 없었으면 비어 있다.
    public let loadWarnings: [String]

    private var configuredBodySize: Int?
    public var noteBodySize: CGFloat { configuredBodySize.map { CGFloat($0) } ?? tokens.textStyle(.body).size }
    /// 설정에서 고른 줄의 여유 공간을 유지하며 본문 글자 크기를 반영한다.
    public var noteBodyLineHeight: CGFloat {
        lineHeight(.body) + noteBodySize - tokens.textStyle(.body).size
    }
    public var defaultBodyLineHeight: CGFloat { baseTokens.textStyle(.body).lineHeight }
    public var defaultBodySize: CGFloat { baseTokens.textStyle(.body).size }

    @ObservationIgnored private var bodyOverrides = ThemeOverrides()
    @ObservationIgnored private let baseTokens: ThemeTokens
    @ObservationIgnored private let overrideStore: ThemeOverrideStore?
    @ObservationIgnored private var appearanceObservation: NSKeyValueObservation?

    /// - Parameters:
    ///   - baseTokens: `tokens.json`에서 읽은 값.
    ///   - overrideStore: 덮어쓰기를 저장할 곳. 있으면 저장된 값을 읽어 얹고, 바꿀 때마다 저장한다.
    ///     저장된 값 가운데 쓸 수 없는 것은 버리고 `loadWarnings`에 적는다(파일은 다음 저장 때 정리된다).
    public init(
        baseTokens: ThemeTokens,
        overrideStore: ThemeOverrideStore? = nil,
        appearance: ThemeAppearance = .light
    ) throws {
        let stored = try overrideStore?.loadRecovering()
        let applied = baseTokens.applyingValid(stored?.overrides ?? ThemeOverrides())
        self.baseTokens = baseTokens
        self.overrideStore = overrideStore
        self.overrides = applied.accepted
        self.tokens = applied.tokens
        self.appearance = appearance
        self.loadWarnings = [stored?.warning].compactMap { $0 }
            + applied.rejected.map { "테마 덮어쓰기를 버렸습니다: \($0)" }
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
        let stored = try baseTokens.applying(newOverrides)
        let newTokens = bodyOverrides.isEmpty ? stored : try stored.applying(bodyOverrides)
        try overrideStore?.save(newOverrides)
        overrides = newOverrides
        tokens = newTokens
        notifyChange()
    }

    /// 기존 테마 파일 위에 앱 설정의 본문 치수만 얹는다. 저장은 AppSettingsStore가 맡는다.
    public func applyBodyTypography(size: Int?, lineHeight: Int?) throws {
        var effective = ThemeOverrides()
        if let lineHeight { effective = effective.setting("type.lh-body", to: "\(lineHeight)px") }
        let next = try baseTokens.applying(overrides).applying(effective)
        bodyOverrides = effective
        guard next != tokens || configuredBodySize != size else { return }
        configuredBodySize = size
        tokens = next
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
