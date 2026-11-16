import Foundation
import Theme

/// 확인용 실행 인자.
///
/// - `--notes-dir <경로>`: 노트 폴더(꼭 있어야 한다. 그 폴더 안만 읽고 쓴다). 비어 있으면 견본 노트를 채운다
/// - `--appearance light|dark`
/// - `--script <단계;단계>`: 차례로 실행할 단계(`DemoScript` 참고)
/// - `--snapshot <경로>`: 스크립트를 마친 뒤 마지막으로 띄운 창의 내용을 PNG로 그려 낸다
/// - `--hold <초>`: 스크립트를 마친 뒤 끝내기 전에 기다리는 시간(창 번호로 화면을 캡처할 때)
/// - `--activate`: 창을 키 창으로 만든다(기본은 다른 앱의 포커스를 빼앗지 않는다)
struct DemoOptions {
    var notesDirectory: URL
    var appearance: ThemeAppearance = .light
    var script: [String] = []
    var snapshotPath: String?
    var hold: Double = 0
    var activates = false

    enum ParseError: Error, CustomStringConvertible {
        case missingValue(String)
        case invalidValue(String, String)
        case unknownFlag(String)
        case missingNotesDirectory

        var description: String {
            switch self {
            case .missingValue(let flag): "\(flag) 뒤에 값이 필요합니다"
            case .invalidValue(let flag, let value): "\(flag)의 값을 읽을 수 없습니다: \(value)"
            case .unknownFlag(let flag): "모르는 인자: \(flag)"
            case .missingNotesDirectory: "--notes-dir <경로>가 필요합니다"
            }
        }
    }

    init(arguments: [String]) throws {
        var remaining = arguments.dropFirst()
        func value(_ flag: String) throws -> String {
            guard let value = remaining.popFirst() else { throw ParseError.missingValue(flag) }
            return value
        }
        var directory: URL?
        while let flag = remaining.popFirst() {
            switch flag {
            case "--notes-dir":
                directory = URL(fileURLWithPath: try value(flag), isDirectory: true)
            case "--appearance":
                let raw = try value(flag)
                guard let parsed = ThemeAppearance(rawValue: raw) else { throw ParseError.invalidValue(flag, raw) }
                appearance = parsed
            case "--script":
                script = try value(flag).split(separator: ";").map { $0.trimmingCharacters(in: .whitespaces) }
            case "--snapshot":
                snapshotPath = try value(flag)
            case "--hold":
                let raw = try value(flag)
                guard let parsed = Double(raw), parsed >= 0 else { throw ParseError.invalidValue(flag, raw) }
                hold = parsed
            case "--activate":
                activates = true
            default:
                throw ParseError.unknownFlag(flag)
            }
        }
        guard let directory else { throw ParseError.missingNotesDirectory }
        notesDirectory = directory
    }
}
