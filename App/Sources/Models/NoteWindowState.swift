import CoreGraphics
import Foundation

/// 화면 좌표의 창 틀(AppKit 좌표: 원점이 왼쪽 아래).
public struct WindowFrame: Hashable, Codable, Sendable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    public init(_ rect: CGRect) {
        self.init(x: rect.origin.x, y: rect.origin.y, width: rect.width, height: rect.height)
    }

    public var cgRect: CGRect {
        CGRect(x: x, y: y, width: width, height: height)
    }
}

/// 노트 창의 로컬 상태. 노트 파일이 아니라 앱 로컬 상태에 저장한다(D-003).
public struct NoteWindowState: Hashable, Codable, Sendable {
    public enum HeightPreference: Hashable, Codable, Sendable {
        case followSetting
        case fixed(Double)

        public var points: CGFloat? {
            if case let .fixed(height) = self { return CGFloat(height) }
            return nil
        }
    }

    public var heightPreference: HeightPreference = .followSetting
    /// 창 틀. 한 번도 띄운 적이 없으면 `nil`.
    public var frame: WindowFrame?
    /// 항상 위에 고정. 새 노트는 켜진 채 만들어진다(spec 4.1).
    public var isPinned: Bool
    /// 지금 창이 떠 있는지. 앱을 다시 켤 때 되살릴 창을 정한다.
    public var isOpen: Bool
    /// 창이 겹친 차례. 앞으로 올 때마다 가장 큰 값보다 하나 큰 값을 받는다(클수록 앞).
    /// 앞으로 온 적이 없으면 `nil`. 앱을 다시 켤 때 이 차례대로 되살려 앞뒤를 지킨다.
    public var stackOrder: Int?
    /// 접어 둔 토글의 줄 번호(0부터, 오름차순). 본문에 적지 않는 보기 상태다(D-018). 접힌 것이 없으면 `nil`.
    public var foldedLines: [Int]?
    /// `foldedLines`의 줄마다 그때의 줄 글(같은 차례, 같은 개수). 창이 닫힌 사이에 파일이 바뀌어 줄 번호가
    /// 어긋났는지 다시 열 때 이것으로 알아보고, 같은 글의 줄을 찾아 옮기거나 버린다(D-023).
    /// 이것 없이 적힌 예전 상태에서는 `nil`이다.
    public var foldedLineTexts: [String]?
    /// 이 노트가 마지막으로 키 창이 된 때. 기존에 기록된 시각은 이어 쓴다(D-130).
    /// 기록이 없으면 최근에서 제외하고 검색으로 찾는다.
    public var lastOpened: Date?
    public struct ReadingPosition: Hashable, Codable, Sendable {
        public var selection: NSRange
        public var scrollY: Double

        public init(selection: NSRange, scrollY: Double) {
            self.selection = selection
            self.scrollY = scrollY
        }
    }
    public var readingPosition: ReadingPosition?

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        readingPosition = try values.decodeIfPresent(ReadingPosition.self, forKey: .readingPosition)
        frame = try values.decodeIfPresent(WindowFrame.self, forKey: .frame)
        // 옛 파일에는 마지막 프레임만 있다. 새 파일은 자동 높이도 명시한다.
        heightPreference = try values.decodeIfPresent(HeightPreference.self, forKey: .heightPreference)
            ?? frame.map { .fixed($0.height) } ?? .followSetting
        isPinned = try values.decode(Bool.self, forKey: .isPinned)
        isOpen = try values.decode(Bool.self, forKey: .isOpen)
        stackOrder = try values.decodeIfPresent(Int.self, forKey: .stackOrder)
        foldedLines = try values.decodeIfPresent([Int].self, forKey: .foldedLines)
        foldedLineTexts = try values.decodeIfPresent([String].self, forKey: .foldedLineTexts)
        lastOpened = try values.decodeIfPresent(Date.self, forKey: .lastOpened)
    }

    public init(
        frame: WindowFrame? = nil, isPinned: Bool = true, isOpen: Bool = false, stackOrder: Int? = nil,
        foldedLines: [Int]? = nil, foldedLineTexts: [String]? = nil, lastOpened: Date? = nil
    ) {
        self.frame = frame
        self.isPinned = isPinned
        self.isOpen = isOpen
        self.stackOrder = stackOrder
        self.foldedLines = foldedLines
        self.foldedLineTexts = foldedLineTexts
        self.lastOpened = lastOpened
    }
}
