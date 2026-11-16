import Foundation
import Models
import Theme

/// 실행 인자. 자동 확인과 디버깅에 쓴다.
///
/// - `--notes-dir <경로>`: 그 폴더만 읽고 쓴다(상태도 그 안의 `.state/`). 실제 노트를 건드리지 않는다.
/// - `--appearance light|dark`: 시스템 설정과 상관없이 모양을 고정한다.
/// - `--debug-hover <노트 id>`: 그 노트를 마우스가 올라간 모습으로 띄운다. 여러 번 쓸 수 있다.
/// - `--debug-control`: 다른 프로세스가 보내는 확인용 명령을 받는다(`DebugControl`).
struct LaunchOptions: Equatable {
    var notesDirectory: URL?
    var appearance: ThemeAppearance?
    var debugHover: [NoteID] = []
    var debugControl = false

    enum ParseError: Error, Equatable, CustomStringConvertible {
        case missingValue(String)
        case invalidAppearance(String)

        var description: String {
            switch self {
            case .missingValue(let flag): "\(flag) 뒤에 값이 필요합니다"
            case .invalidAppearance(let value): "--appearance는 light 또는 dark여야 합니다: \(value)"
            }
        }
    }

    /// 모르는 인자는 넘어간다(macOS가 붙이는 인자가 있다).
    init(arguments: [String]) throws {
        var remaining = arguments.dropFirst()
        func value(after flag: String) throws -> String {
            guard let value = remaining.popFirst() else { throw ParseError.missingValue(flag) }
            return value
        }
        while let flag = remaining.popFirst() {
            switch flag {
            case "--notes-dir":
                notesDirectory = URL(fileURLWithPath: try value(after: flag), isDirectory: true)
            case "--appearance":
                let raw = try value(after: flag)
                guard let parsed = ThemeAppearance(rawValue: raw) else {
                    throw ParseError.invalidAppearance(raw)
                }
                appearance = parsed
            case "--debug-hover":
                debugHover.append(NoteID(rawValue: try value(after: flag)))
            case "--debug-control":
                debugControl = true
            default:
                continue
            }
        }
    }
}
