import Foundation

/// 코드 블록의 언어 이름으로 받는 낱말. 세 번째 백틱 바로 뒤에 친 낱말이 여기 있을 때만 언어 이름으로 옮긴다
/// (`ls`, `x`, `main` 같은 한 낱말짜리 코드 줄이 보이지 않는 이름이 되지 않게).
nonisolated enum CodeLanguages {
    static let known: Set<String> = [
        "swift", "objc", "objective-c", "c", "cpp", "c++", "cs", "csharp", "c#", "rust", "go",
        "python", "py", "javascript", "js", "typescript", "ts", "tsx", "jsx",
        "json", "yaml", "yml", "toml", "html", "css", "scss", "xml", "sql",
        "bash", "sh", "zsh", "shell", "ruby", "rb", "java", "kotlin", "php", "lua", "r", "dart",
        "diff", "markdown", "md", "plaintext", "text", "txt",
    ]

    /// 대소문자는 가리지 않는다(`Swift`, `JSON`).
    static func isKnown(_ word: String) -> Bool {
        known.contains(word.lowercased())
    }
}
