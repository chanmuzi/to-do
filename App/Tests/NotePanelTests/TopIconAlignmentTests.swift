import AppKit
import Testing
import Theme
@testable import NotePanel

@MainActor @Suite struct TopIconAlignmentTests {
    @Test func clockAndPinShareTheButtonCenterAndIconSlot() throws {
        let theme = try Theme.bundled()
        let style = PanelStyle(theme: theme)
        let side = theme.component(.iconButton)
        let frame = NSRect(x: 0, y: 0, width: side, height: side)
        let pin = IconButton(style: style, symbolName: "pin.fill", iconSize: .iconMedium, label: "핀")
        pin.frame = frame
        pin.layout()
        let reminder = IconButton(style: style, symbolName: "clock", iconSize: .iconMedium, label: "예정")
        reminder.frame = frame
        reminder.layout()
        for view in [pin, reminder] {
            let image = try #require(view.subviews.compactMap { $0 as? NSImageView }.first)
            #expect(image.frame.midX == side / 2)
            #expect(image.frame.midY == side / 2)
            #expect(max(image.image?.size.width ?? 0, image.image?.size.height ?? 0) <= theme.component(.iconMedium))
        }
    }

    @Test func libraryCanBeDisabledWithoutMovingItsRow() throws {
        let menu = NoteMenuBuilder(style: PanelStyle(theme: try Theme.bundled())).moreMenu(
            isPinned: true, selectedPaletteID: nil, isAvailable: { $0 != .openLibrary }) { _ in
                Issue.record("연결되지 않은 메뉴가 실행됐습니다")
            }
        let index = try #require(menu.items.firstIndex { $0.title == "라이브러리" })
        #expect(menu.items[index - 1].title == "노트 찾기")
        #expect(!menu.items[index].isEnabled)
        menu.performActionForItem(at: index)
    }
}
