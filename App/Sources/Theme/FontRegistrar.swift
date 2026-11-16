import CoreText
import Foundation

/// 글꼴 등록 결과. 등록하지 못한 글꼴이 있어도 앱은 시스템 글꼴로 계속 간다(`FontResolver`가 대신 고른다).
public struct FontRegistration: Hashable, Sendable {
    /// 등록한 글꼴 파일(이름 순).
    public let registered: [URL]
    /// 등록하지 못한 것의 설명. 앱이 켤 때 모아서 기록한다.
    public let problems: [String]
}

/// 앱 글꼴(Pretendard, D2Coding)을 이 프로세스에 등록한다. 앱을 켤 때 한 번 부른다.
public enum FontRegistrar {
    /// 번들의 `Fonts/` 폴더에 있는 글꼴을 등록한다. 실패해도 던지지 않고 `problems`에 적는다.
    @discardableResult
    public static func registerBundledFonts() -> FontRegistration {
        do {
            return registerFonts(in: try ThemeResources.fontsDirectoryURL())
        } catch {
            return FontRegistration(registered: [], problems: ["\(error)"])
        }
    }

    @discardableResult
    public static func registerFonts(in directory: URL) -> FontRegistration {
        let files: [URL]
        do {
            files = try FileManager.default
                .contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
                .filter { ["ttf", "otf"].contains($0.pathExtension.lowercased()) }
                .sorted { $0.lastPathComponent < $1.lastPathComponent }
        } catch {
            return FontRegistration(registered: [], problems: ["\(ThemeError.resourceNotFound(directory.path))"])
        }
        guard !files.isEmpty else {
            return FontRegistration(registered: [], problems: ["\(ThemeError.resourceNotFound("Fonts/*.ttf"))"])
        }
        let failures = files.compactMap { file in register(file).map { (file, $0) } }
        return FontRegistration(
            registered: files.filter { file in !failures.contains { $0.0 == file } },
            problems: failures.map { "\($0.1)" }
        )
    }

    /// 실패했으면 그 오류.
    private static func register(_ file: URL) -> ThemeError? {
        var error: Unmanaged<CFError>?
        if CTFontManagerRegisterFontsForURL(file as CFURL, .process, &error) { return nil }
        let failure = error?.takeRetainedValue()
        // 같은 프로세스에서 두 번 부른 경우다. 글꼴은 이미 쓸 수 있다.
        if let failure, CFErrorGetCode(failure) == CTFontManagerError.alreadyRegistered.rawValue { return nil }
        return .fontRegistrationFailed(
            file: file.lastPathComponent,
            reason: failure.map { CFErrorCopyDescription($0) as String } ?? "알 수 없는 오류"
        )
    }
}
