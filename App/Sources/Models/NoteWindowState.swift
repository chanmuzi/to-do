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
    /// 창 틀. 한 번도 띄운 적이 없으면 `nil`.
    public var frame: WindowFrame?
    /// 항상 위에 고정. 새 노트는 켜진 채 만들어진다(spec 4.1).
    public var isPinned: Bool
    /// 지금 창이 떠 있는지. 앱을 다시 켤 때 되살릴 창을 정한다.
    public var isOpen: Bool
    /// 창이 겹친 차례. 앞으로 올 때마다 가장 큰 값보다 하나 큰 값을 받는다(클수록 앞).
    /// 앞으로 온 적이 없으면 `nil`. 앱을 다시 켤 때 이 차례대로 되살려 앞뒤를 지킨다.
    public var stackOrder: Int?

    public init(
        frame: WindowFrame? = nil, isPinned: Bool = true, isOpen: Bool = false, stackOrder: Int? = nil
    ) {
        self.frame = frame
        self.isPinned = isPinned
        self.isOpen = isOpen
        self.stackOrder = stackOrder
    }
}
