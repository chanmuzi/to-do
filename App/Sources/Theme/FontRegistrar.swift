import CoreText
import Foundation

/// 앱 글꼴(Pretendard, D2Coding)을 이 프로세스에 등록한다. 앱을 켤 때 한 번 부른다.
public enum FontRegistrar {
    /// 번들의 `Fonts/` 폴더에 있는 글꼴을 모두 등록하고 등록한 파일을 돌려준다.
    @discardableResult
    public static func registerBundledFonts() throws -> [URL] {
        try registerFonts(in: ThemeResources.fontsDirectoryURL())
    }

    @discardableResult
    public static func registerFonts(in directory: URL) throws -> [URL] {
        let files = try FileManager.default
            .contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { ["ttf", "otf"].contains($0.pathExtension.lowercased()) }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        guard !files.isEmpty else { throw ThemeError.resourceNotFound("Fonts/*.ttf") }
        for file in files { try register(file) }
        return files
    }

    private static func register(_ file: URL) throws {
        var error: Unmanaged<CFError>?
        if CTFontManagerRegisterFontsForURL(file as CFURL, .process, &error) { return }
        let failure = error?.takeRetainedValue()
        // 같은 프로세스에서 두 번 부른 경우다. 글꼴은 이미 쓸 수 있다.
        if let failure, CFErrorGetCode(failure) == CTFontManagerError.alreadyRegistered.rawValue { return }
        throw ThemeError.fontRegistrationFailed(
            file: file.lastPathComponent,
            reason: failure.map { CFErrorCopyDescription($0) as String } ?? "알 수 없는 오류"
        )
    }
}
