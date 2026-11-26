import Foundation

/// 1에서 4까지의 바탕색 식별자는 기존 파일의 색 번호와 같다.
nonisolated package enum InkHue: Int, CaseIterable, Sendable {
    case yellow = 1, gray, red, blue, brown, orange, green, purple, pink

    package static let palette: [Self] = [.gray, .brown, .orange, .yellow, .green, .blue, .purple, .pink, .red]

    package var name: String {
        switch self {
        case .gray: "회색"
        case .brown: "갈색"
        case .orange: "주황"
        case .yellow: "노랑"
        case .green: "초록"
        case .blue: "파랑"
        case .purple: "보라"
        case .pink: "분홍"
        case .red: "빨강"
        }
    }
}

nonisolated package struct InkColor: Hashable, Sendable {
    package let hue: InkHue
    package let foreground: Bool

    package init(_ hue: InkHue, foreground: Bool = false) {
        self.hue = hue
        self.foreground = foreground
    }

    package static let palette = [true, false].flatMap { foreground in
        InkHue.palette.map { InkColor($0, foreground: foreground) }
    }

    package var id: Int { foreground ? hue.rawValue + InkHue.allCases.count : hue.rawValue }
    package static let byID = Dictionary(uniqueKeysWithValues: palette.map { ($0.id, $0) })
    package var label: String { hue.name + (foreground ? " 글자" : " 바탕") }
    package var suffix: String { foreground ? label : hue.name }
    package var comment: String { " <!-- " + label + " -->" }

    static let bySuffix: [String: Self] = {
        var values = Dictionary(uniqueKeysWithValues: palette.map { ($0.suffix, $0) })
        for id in 1...4 { values[String(id)] = byID[id] }
        return values
    }()
    static let byLabel = Dictionary(uniqueKeysWithValues: palette.map { ($0.label, $0) })
}
