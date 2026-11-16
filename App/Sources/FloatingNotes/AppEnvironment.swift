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
    let registeredFonts: [URL]

    init(options: LaunchOptions) throws {
        location = try options.notesDirectory.map(StoreLocation.isolated) ?? .standard()
        registeredFonts = try FontRegistrar.registerBundledFonts()
        theme = try Theme.bundled(
            overrideStore: ThemeOverrideStore(
                url: location.stateDirectory.appendingPathComponent("theme-overrides.json")
            )
        )
        notes = try FileNoteStore(location: location)
        windowStates = try WindowStateStore(location: location)
        spaces = try SpaceStore(location: location)
    }
}
