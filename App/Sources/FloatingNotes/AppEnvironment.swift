import AppKit
import Store
import Theme

/// 앱이 공유하는 바탕(테마, 저장소)을 한 번 만들어 들고 있는 조립 지점.
/// 기능 모듈에는 여기서 필요한 것만 꺼내 넘긴다.
final class AppEnvironment {
    let location: StoreLocation
    let theme: Theme
    let notes: FileNoteStore
    let windowStates: WindowStateStore
    let spaces: SpaceStore
    let settings: AppSettingsStore
    let registeredFonts: [URL]
    /// 켜는 동안 문제가 있어 기본값으로 넘어간 것들(글꼴 등록 실패, 버린 테마 덮어쓰기, 망가진 상태 파일).
    /// 앱은 계속 켜지고, `AppDelegate`가 기록한다.
    let launchWarnings: [String]

    init(options: LaunchOptions) throws {
        location = try options.notesDirectory.map(StoreLocation.isolated) ?? .standard()
        let fonts = FontRegistrar.registerBundledFonts()
        registeredFonts = fonts.registered
        theme = try Theme.bundled(
            overrideStore: ThemeOverrideStore(
                url: location.stateDirectory.appendingPathComponent("theme-overrides.json")
            )
        )
        notes = try FileNoteStore(location: location)
        // 창을 띄우거나 키 창이 될 때마다 잇달아 오는 창 상태 변경은 한 번에 모아 쓴다. 끝낼 때 `flush()`한다.
        windowStates = try WindowStateStore(
            location: location, writeDelay: WindowStateStore.coalescingWriteDelay
        )
        windowStates.onWriteFailure = { AppLog.warning("창 상태를 저장하지 못했습니다: \($0)") }
        spaces = try SpaceStore(location: location)
        settings = try AppSettingsStore(stateDirectory: location.stateDirectory)
        launchWarnings = fonts.problems + theme.loadWarnings
            + [windowStates.loadWarning, spaces.loadWarning, settings.loadWarning].compactMap { $0 }
    }
}
