import Foundation
import Models
import Theme

/// 실행 인자. 자동 확인과 디버깅에 쓴다.
///
/// - `--notes-dir <경로>`: 그 폴더만 읽고 쓴다(상태도 그 안의 `.state/`). 실제 노트를 건드리지 않는다.
/// - `--appearance light|dark`: 시스템 설정과 상관없이 모양을 고정한다.
/// - `--menu-bar-icon on|off`: 저장된 설정과 상관없이 이번 실행에서 메뉴 막대 아이콘을 보이거나 감춘다.
///
/// 디버그 빌드에만 있는 것(릴리스 빌드는 이 인자를 모른다):
/// - `--debug-hover <노트 id>`: 그 노트를 마우스가 올라간 모습으로 띄운다. 여러 번 쓸 수 있다.
/// - `--debug-control <출력 폴더>`: 다른 프로세스가 보내는 확인용 명령을 받는다(`DebugControl`).
///   명령이 쓰는 파일은 이 폴더 안에만 생긴다.
/// - `--debug-passive`: 노트 창이 키 창이 되지 않게 한다. 노트 창은 앱이 앞에 있지 않아도 키 창이 되어
///   사용자가 다른 앱에 치던 글자를 받는다. 자동 확인 실행은 이것을 켜고, 확인용 명령 `focus`만 잠깐 푼다.
/// - `--debug-no-hotkeys`: 전역 단축키를 등록하지 않는다. 확인용 실행이 사용자의 키를 가로채지 않게 한다.
struct LaunchOptions: Equatable {
    var notesDirectory: URL?
    var appearance: ThemeAppearance?
    /// 이번 실행에서만 메뉴 막대 아이콘을 보일지. `nil`이면 저장된 설정을 따른다.
    var menuBarIconOverride: Bool?
    #if DEBUG
    var debugHover: [NoteID] = []
    /// 확인용 명령을 받을 때 그 명령이 파일을 쓸 수 있는 하나뿐인 폴더. 없으면 명령을 받지 않는다.
    var debugControlDirectory: URL?
    var debugSkipsHotKeys = false
    var debugIsPassive = false
    #endif

    enum ParseError: Error, Equatable, CustomStringConvertible {
        case missingValue(String)
        case invalidAppearance(String)
        case invalidSwitch(flag: String, value: String)

        var description: String {
            switch self {
            case .missingValue(let flag): "\(flag) 뒤에 값이 필요합니다"
            case .invalidAppearance(let value): "--appearance는 light 또는 dark여야 합니다: \(value)"
            case .invalidSwitch(let flag, let value): "\(flag)는 on 또는 off여야 합니다: \(value)"
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
            case "--menu-bar-icon":
                let raw = try value(after: flag)
                guard raw == "on" || raw == "off" else { throw ParseError.invalidSwitch(flag: flag, value: raw) }
                menuBarIconOverride = raw == "on"
            #if DEBUG
            case "--debug-hover":
                debugHover.append(NoteID(rawValue: try value(after: flag)))
            case "--debug-control":
                debugControlDirectory = URL(fileURLWithPath: try value(after: flag), isDirectory: true)
            case "--debug-passive":
                debugIsPassive = true
            case "--debug-no-hotkeys":
                debugSkipsHotKeys = true
            #endif
            default:
                continue
            }
        }
    }
}
