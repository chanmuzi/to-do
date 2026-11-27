import MarkdownSyntax

/// Notion HTML 내보내기에서 쓰는 이름. 앱 테마와 독립적인 교환 형식이다.
nonisolated enum NotionHTMLFormat {
    static let headingSizes = [1: "1.875em", 2: "1.5em", 3: "1.25em"]

    static func colorName(_ ink: InkColor) -> String {
        let hue: String
        switch ink.hue {
        case .gray: hue = "gray"
        case .brown: hue = "brown"
        case .orange: hue = "orange"
        case .yellow: hue = "yellow"
        case .green: hue = "teal"
        case .blue: hue = "blue"
        case .purple: hue = "purple"
        case .pink: hue = "pink"
        case .red: hue = "red"
        }
        return hue + (ink.foreground ? "" : "_background")
    }

    static let colors = Dictionary(uniqueKeysWithValues: InkColor.palette.map { (colorName($0), $0) })
}
