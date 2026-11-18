import Foundation
import Observation
import FloatSettings

typealias AppSettings = SettingsValues

/// `AppSettings`를 `stateDirectory/app-settings.json`에 둔다.
@Observable
final class AppSettingsStore {
    private let url: URL
    private(set) var settings: AppSettings
    /// 저장된 파일을 읽지 못해 기본값으로 시작했으면 그 설명. 앱이 켤 때 모아서 기록한다.
    let loadWarning: String?
    /// 설정이 바뀌어 파일에 적힌 뒤에 부른다. 떠 있는 화면에 곧바로 반영하는 쪽이 건다.
    @ObservationIgnored var onChange: ((AppSettings) -> Void)?

    /// 파일이 망가져 있으면 지우지 않고 옆으로 옮겨 두고(`app-settings.json.corrupt`) 기본값으로 시작한다.
    /// 옮기지도 못하면 던진다(그대로 두면 다음 저장이 덮어쓴다).
    init(stateDirectory: URL) throws {
        url = stateDirectory.appendingPathComponent("app-settings.json")
        guard FileManager.default.fileExists(atPath: url.path) else {
            settings = AppSettings()
            loadWarning = nil
            return
        }
        do {
            settings = try JSONDecoder().decode(AppSettings.self, from: Data(contentsOf: url))
            loadWarning = nil
        } catch {
            let aside = try Self.moveAside(url)
            settings = AppSettings()
            loadWarning = "\(url.lastPathComponent)을 읽지 못해 기본 설정으로 시작합니다. "
                + "원래 파일은 \(aside.lastPathComponent)로 옮겨 두었습니다. (\(error))"
        }
    }

    /// 바꾸고 곧바로 파일에 쓴다. 쓰지 못하면 던지고 아무것도 바꾸지 않는다.
    func update(_ change: (inout AppSettings) -> Void) throws {
        var changed = settings
        change(&changed)
        guard changed != settings else { return }
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(changed).write(to: url, options: .atomic)
        settings = changed
        onChange?(changed)
    }

    private static func moveAside(_ url: URL) throws -> URL {
        let directory = url.deletingLastPathComponent()
        let base = url.lastPathComponent + ".corrupt"
        var candidate = directory.appendingPathComponent(base)
        var suffix = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = directory.appendingPathComponent("\(base)-\(suffix)")
            suffix += 1
        }
        try FileManager.default.moveItem(at: url, to: candidate)
        return candidate
    }
}
