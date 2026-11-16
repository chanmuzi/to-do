import Foundation
import Theme

/// 실행 인자. 자동 확인과 디버깅에 쓴다.
///
/// - `--notes-dir <경로>`: 그 폴더만 읽고 쓴다(상태도 그 안의 `.state/`). 실제 노트를 건드리지 않는다.
/// - `--appearance light|dark`: 시스템 설정과 상관없이 모양을 고정한다.
struct LaunchOptions: Equatable {
    var notesDirectory: URL?
    var appearance: ThemeAppearance?

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
        while let flag = remaining.popFirst() {
            switch flag {
            case "--notes-dir":
                guard let path = remaining.popFirst() else { throw ParseError.missingValue(flag) }
                notesDirectory = URL(fileURLWithPath: path, isDirectory: true)
            case "--appearance":
                guard let value = remaining.popFirst() else { throw ParseError.missingValue(flag) }
                guard let parsed = ThemeAppearance(rawValue: value) else {
                    throw ParseError.invalidAppearance(value)
                }
                appearance = parsed
            default:
                continue
            }
        }
    }
}
