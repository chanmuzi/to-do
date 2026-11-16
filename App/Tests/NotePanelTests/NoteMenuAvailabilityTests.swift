import AppKit
import Routing
import Testing
import Theme
@testable import NotePanel

/// 더 보기 메뉴에서 아직 이어지지 않은 화면을 여는 항목은 자리를 지킨 채 고를 수 없다(D-034).
@Suite @MainActor struct NoteMenuAvailabilityTests {
    @Test func rowsForUnavailableActionsAreDisabledInPlace() throws {
        let builder = NoteMenuBuilder(style: PanelStyle(theme: try Theme.bundled()))
        var chosen: [MoreMenuAction] = []
        let unavailable: Set<MoreMenuAction> = [.setReminder, .moveToSpace, .openAIPanel]
        let menu = builder.moreMenu(
            isPinned: true, selectedPaletteID: nil, isAvailable: { !unavailable.contains($0) }
        ) { chosen.append($0) }

        #expect(menu.items.filter { !$0.isSeparatorItem }.map(\.title) == [
            "리마인더 설정", "스페이스 옮기기", "항상 위에 고정", "노트 색", "AI 패널 열기", "창 닫기", "휴지통으로 보내기",
        ])
        #expect(menu.items.filter { !$0.isSeparatorItem && !$0.isEnabled }.map(\.title) == [
            "리마인더 설정", "스페이스 옮기기", "AI 패널 열기",
        ])
        for index in menu.items.indices where menu.items[index].action != nil {
            menu.performActionForItem(at: index)
        }
        #expect(chosen == [.togglePin, .closeWindow, .moveToTrash])

        // 모두 이어져 있으면(기본) 전부 고를 수 있다.
        let all = builder.moreMenu(isPinned: false, selectedPaletteID: nil) { _ in }
        #expect(all.items.filter { !$0.isSeparatorItem && $0.action != nil && !$0.isEnabled }.isEmpty)
    }
}
