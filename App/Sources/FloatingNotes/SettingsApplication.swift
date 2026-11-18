import AppKit
import Theme

/// 파일에 성공적으로 쓴 설정을 기존 창과 다음에 열 창에 함께 전달한다.
enum SettingsApplication {
    static func follow(_ store: AppSettingsStore, theme: Theme, appearanceOverride: ThemeAppearance?,
                       setAppearance: @escaping (NSAppearance?) -> Void,
                       applyDisplay: @escaping (NoteDisplayOptions, Bool) -> Void,
                       showMenuIcon: @escaping (Bool) -> Void) {
        var previous: AppSettings?
        func apply(_ values: AppSettings) {
            if previous?.appearance != values.appearance {
                setAppearance((appearanceOverride ?? ThemeAppearance(rawValue: values.appearance))?.nsAppearance)
            }
            if previous?.bodySize != values.bodySize || previous?.bodyLineHeight != values.bodyLineHeight {
                do { try theme.applyBodyTypography(size: values.bodySize, lineHeight: values.bodyLineHeight) }
                catch { AppLog.warning("본문 치수를 적용하지 못했습니다: \(error)") }
            }
            let display = NoteDisplayOptions(dateFormat: .init(rawValue: values.scheduleDateFormat) ?? .relative,
                space: .init(rawValue: values.spaceDisplay) ?? .icon,
                reminder: .init(rawValue: values.reminderDisplay) ?? .time,
                clock: .init(rawValue: values.clockFormat) ?? .koreanMeridiem)
            applyDisplay(display, values.recognizesDates)
            if previous?.showsMenuBarIcon != values.showsMenuBarIcon { showMenuIcon(values.showsMenuBarIcon) }
            previous = values
        }
        apply(store.settings)
        let prior = store.onChange
        store.onChange = { values in
            prior?(values)
            apply(values)
        }
    }
}
