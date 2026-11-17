import Editor
import Foundation
import Theme

/// 확인용 실행 인자.
///
/// - `--appearance light|dark`
/// - `--checkbox box|bracket`
/// - `--code-style accent|plain`: 인라인 코드의 글자색(기본 `accent`)
/// - `--sample note|elements|code|literal|structure|empty`: 미리 넣을 내용(기본 `note`, 화면 2의 노트)
/// - `--caret-line <n>`: 커서를 둘 줄(0부터). 그 줄 끝에 놓는다
/// - `--fold <n,n>`: 접어 둘 토글의 줄 번호
/// - `--width <pt>`: 창 너비(기본 340)
/// - `--origin <x,y>`: 창 왼쪽 위의 화면 좌표(기본 40,40)
/// - `--script <단계;단계>`: 띄운 뒤 차례로 실행할 입력(`DemoScript` 참고)
/// - `--print-text`: 스크립트를 마친 뒤 원문을 표준 출력에 적는다
/// - `--activate`: 창을 키 창으로 만든다(기본은 다른 앱의 포커스를 빼앗지 않는다)
/// - `--quit-after <초>`: 그만큼 뒤에 스스로 끝낸다(키 창으로 띄워 화면에서 볼 때. 띄워 둔 채 남지 않게)
/// - `--snapshot <경로>`: 창 내용을 PNG로 그려 내고 끝낸다(화면 녹화 권한 없이 그 창만 찍는다)
struct DemoOptions {
    var appearance: ThemeAppearance = .light
    var checkboxStyle: CheckboxStyle = .box
    var inlineCodeStyle: InlineCodeStyle = .accent
    var sample = "note"
    var caretLine: Int?
    var folded: Set<Int> = []
    var width: Double = 340
    var origin: (x: Double, y: Double) = (40, 40)
    var script: [String] = []
    var printsText = false
    var activates = false
    var snapshotPath: String?
    var quitAfter: Double?

    enum ParseError: Error, CustomStringConvertible {
        case missingValue(String)
        case invalidValue(String, String)

        var description: String {
            switch self {
            case .missingValue(let flag): "\(flag) 뒤에 값이 필요합니다"
            case .invalidValue(let flag, let value): "\(flag)의 값을 읽을 수 없습니다: \(value)"
            }
        }
    }

    init(arguments: [String]) throws {
        var remaining = arguments.dropFirst()
        func value(_ flag: String) throws -> String {
            guard let value = remaining.popFirst() else { throw ParseError.missingValue(flag) }
            return value
        }
        while let flag = remaining.popFirst() {
            switch flag {
            case "--appearance":
                let raw = try value(flag)
                guard let parsed = ThemeAppearance(rawValue: raw) else { throw ParseError.invalidValue(flag, raw) }
                appearance = parsed
            case "--checkbox":
                let raw = try value(flag)
                guard let parsed = CheckboxStyle(rawValue: raw) else { throw ParseError.invalidValue(flag, raw) }
                checkboxStyle = parsed
            case "--code-style":
                let raw = try value(flag)
                guard let parsed = InlineCodeStyle(rawValue: raw) else { throw ParseError.invalidValue(flag, raw) }
                inlineCodeStyle = parsed
            case "--sample":
                sample = try value(flag)
            case "--caret-line":
                let raw = try value(flag)
                guard let parsed = Int(raw) else { throw ParseError.invalidValue(flag, raw) }
                caretLine = parsed
            case "--fold":
                let raw = try value(flag)
                let numbers = raw.split(separator: ",").map { Int($0) }
                guard !numbers.contains(nil) else { throw ParseError.invalidValue(flag, raw) }
                folded = Set(numbers.compactMap { $0 })
            case "--width":
                let raw = try value(flag)
                guard let parsed = Double(raw), parsed > 0 else { throw ParseError.invalidValue(flag, raw) }
                width = parsed
            case "--origin":
                let raw = try value(flag)
                let parts = raw.split(separator: ",").compactMap { Double($0) }
                guard parts.count == 2 else { throw ParseError.invalidValue(flag, raw) }
                origin = (parts[0], parts[1])
            case "--script":
                script = try value(flag).split(separator: ";").map(String.init)
            case "--print-text":
                printsText = true
            case "--activate":
                activates = true
            case "--quit-after":
                let raw = try value(flag)
                guard let parsed = Double(raw), parsed > 0 else { throw ParseError.invalidValue(flag, raw) }
                quitAfter = parsed
            case "--snapshot":
                snapshotPath = try value(flag)
            default:
                continue
            }
        }
    }
}
