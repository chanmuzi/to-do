import Foundation

/// 링크로 다루는 주소. 웹 주소와 메일 주소만 열고, HTML로 내보낼 때도 이것만 `href`에 넣는다
/// (`javascript:`, `file:`, 다른 앱을 여는 주소는 글자로만 둔다).
nonisolated enum LinkPolicy {
    static let allowedSchemes: Set<String> = ["http", "https", "mailto"]

    /// 열어도 되는 주소면 그 URL.
    static func openableURL(_ address: String) -> URL? {
        let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), let scheme = url.scheme?.lowercased(),
              allowedSchemes.contains(scheme) else { return nil }
        return url
    }
}
