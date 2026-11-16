import Foundation

/// 번들에 든 테마 리소스의 위치.
/// `.app`으로 묶였을 때는 `Contents/Resources/`에서, `swift run`·`swift test`에서는 SwiftPM 리소스 번들에서 찾는다.
public enum ThemeResources {
    public static func tokensURL() throws -> URL {
        try locate("tokens.json")
    }

    public static func fontsDirectoryURL() throws -> URL {
        try locate("Fonts")
    }

    private static func locate(_ name: String) throws -> URL {
        let fileManager = FileManager.default
        if let url = Bundle.main.resourceURL?.appendingPathComponent(name),
           fileManager.fileExists(atPath: url.path) {
            return url
        }
        // 앱 묶음 밖에서만 여기로 온다. Bundle.module은 번들이 없으면 멈추므로 위를 먼저 본다.
        if let url = Bundle.module.resourceURL?.appendingPathComponent(name),
           fileManager.fileExists(atPath: url.path) {
            return url
        }
        throw ThemeError.resourceNotFound(name)
    }
}
