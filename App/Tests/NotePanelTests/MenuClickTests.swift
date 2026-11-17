import AppKit
import Testing
import Theme
@testable import NotePanel

/// 더 보기 메뉴의 줄과 색 칸을 실제 마우스 이벤트로 누른다.
///
/// 열린 메뉴는 AppKit이 따로 돌리는 추적 루프라 시험에서 띄우지 않는다(띄우면 닫힐 때까지 돌아오지 않는다).
/// 메뉴가 줄 뷰에 하는 일, 곧 그 점의 뷰를 찾고(`hitTest`) 그 뷰에 뗀 이벤트를 건네는 일을 그대로 한다.
@Suite @MainActor struct MenuClickTests {
    private let style: PanelStyle

    init() throws {
        style = PanelStyle(theme: try Theme.bundled())
    }

    private func mouseUp(at point: NSPoint = .zero, windowNumber: Int = 0) -> NSEvent {
        NSEvent.mouseEvent(
            with: .leftMouseUp, location: point, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 0
        )!
    }

    /// 줄 어디를 눌러도(아이콘, 글자, 빈 곳) 줄이 통째로 받고, 한 번 떼면 그 동작이 한 번 간다.
    @Test func everyRowActsOnceWhereverItIsPressed() {
        var chosen: [MoreMenuAction] = []
        let menu = NoteMenuBuilder(style: style).moreMenu(isPinned: true, selectedPaletteID: nil) { chosen.append($0) }
        let rows = menu.items.compactMap { $0.view as? MenuRowView }
        #expect(rows.count == 7)
        for row in rows {
            row.layoutSubtreeIfNeeded()
            for x in stride(from: 1.0, through: row.bounds.width - 1, by: 7) {
                for y in stride(from: 1.0, through: row.bounds.height - 1, by: 6) {
                    #expect(row.hitTest(NSPoint(x: x, y: y)) === row)
                }
            }
            let before = chosen.count
            row.mouseUp(with: mouseUp())
            #expect(chosen.count == before + 1, "\(row)")
        }
        #expect(chosen == [
            .setReminder, .moveToSpace, .togglePin, .findNote, .openAIPanel, .closeWindow, .moveToTrash,
        ])
    }

    /// 색 칸은 실제 누름(창의 이벤트 길)으로 그 색을 고른다. 칸 사이의 틈은 아무것도 고르지 않는다.
    @Test func swatchesSelectTheirColourOnARealPress() throws {
        var selected: [String?] = []
        let row = ColorSwatchRowView(style: style, selectedPaletteID: nil) { selected.append($0) }
        let window = NSWindow(
            contentRect: NSRect(x: -4000, y: -4000, width: row.frame.width, height: row.frame.height),
            styleMask: .borderless, backing: .buffered, defer: false
        )
        window.isReleasedWhenClosed = false
        defer { window.close() }
        window.contentView = row
        // 화면 밖에 띄운다. 띄우지 않은 창은 마우스 이벤트를 뷰에 건네지 않는다.
        window.orderFrontRegardless()
        row.layoutSubtreeIfNeeded()
        let swatches = row.subviews.compactMap { $0 as? SwatchView }
        #expect(swatches.count == 1 + style.theme.palette.count)
        for swatch in swatches {
            RealClick.click(swatch)
        }
        #expect(selected == [nil] + style.theme.palette.map { Optional($0.id) }, "\(selected)")
    }
}

/// 더 보기 메뉴의 줄, 색 줄, 구분선은 불투명한 `surface` 바탕이다(흰 노트, 색 노트 위에서도 글자가 바래지 않게).
@Suite @MainActor struct MenuSurfaceTests {
    @Test func moreMenuPaintsAnOpaqueSurfaceInLightAndDark() throws {
        let style = PanelStyle(theme: try Theme.bundled())
        let menu = NoteMenuBuilder(style: style).moreMenu(isPinned: false, selectedPaletteID: nil) { _ in }
        let views = menu.items.compactMap(\.view)
        #expect(views.count == menu.items.count)
        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            for view in views {
                view.appearance = NSAppearance(named: appearance)
                view.updateLayer()
                let color = try #require(view.layer?.backgroundColor, "\(view)")
                #expect(color.alpha == 1, "\(view)")
            }
        }
    }
}
