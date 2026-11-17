import AppKit
import Testing
import Theme
@testable import FloatingNotes

/// 메뉴 막대 메뉴의 줄을 실제 뗀 이벤트로 누른다. 열린 메뉴는 AppKit이 따로 돌리는 추적 루프라 띄우지 않고,
/// 메뉴가 줄 뷰에 하는 일(그 점의 뷰 찾기, 뗀 이벤트 건네기)을 그대로 한다.
@MainActor
@Suite struct StatusMenuClickTests {
    private let theme: Theme

    init() throws {
        theme = try Theme.bundled()
    }

    private let up = NSEvent.mouseEvent(
        with: .leftMouseUp, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil,
        eventNumber: 0, clickCount: 1, pressure: 0
    )!

    @Test func everyEnabledRowActsOnceWhereverItIsPressed() {
        let menu = NSMenu()
        var chosen: [StatusMenuAction] = []
        StatusMenuBuilder(theme: theme).fill(menu, with: StatusMenuModel.entries(areNotesHidden: false)) {
            chosen.append($0)
        }
        for item in menu.items where !item.isSeparatorItem {
            let row = try! #require(item.view as? MenuBarRowView)
            row.layoutSubtreeIfNeeded()
            for x in stride(from: 1.0, through: row.bounds.width - 1, by: 9) {
                #expect(row.hitTest(NSPoint(x: x, y: row.bounds.midY)) === row)
            }
            let before = chosen.count
            row.mouseUp(with: up)
            #expect(chosen.count == before + (item.isEnabled ? 1 : 0), "\(item.title)")
        }
        #expect(chosen.count == menu.items.filter { !$0.isSeparatorItem && $0.isEnabled }.count)
    }

    /// 줄과 구분선은 불투명한 `surface` 바탕이다(메뉴의 반투명 재질이 비쳐 바탕이 탁해지지 않게).
    @Test func rowsAndSeparatorsPaintAnOpaqueSurface() throws {
        let menu = NSMenu()
        StatusMenuBuilder(theme: theme).fill(menu, with: StatusMenuModel.entries(areNotesHidden: false)) { _ in }
        let separators = menu.items.filter(\.isSeparatorItem)
        #expect(separators.allSatisfy { $0.view is MenuBarSeparatorView })
        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            for view in menu.items.compactMap(\.view) {
                view.appearance = NSAppearance(named: appearance)
                view.updateLayer()
                let color = try #require(view.layer?.backgroundColor)
                #expect(color.alpha == 1, "\(view)")
            }
        }
    }
}
