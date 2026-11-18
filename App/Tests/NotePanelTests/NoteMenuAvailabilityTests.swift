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
            "리마인더 설정", "스페이스 옮기기", "항상 위에 고정", "노트 색", "노트 찾기", "라이브러리", "AI 패널 열기", "창 닫기",
            "보관함으로", "휴지통으로 보내기",
        ])
        #expect(menu.items.filter { !$0.isSeparatorItem && !$0.isEnabled }.map(\.title) == [
            "리마인더 설정", "스페이스 옮기기", "AI 패널 열기",
        ])
        // 고를 수 없는 항목은 눌러도 동작이 가지 않고, 고를 수 있는 항목은 간다.
        menu.performActionForItem(at: try #require(menu.items.firstIndex { $0.title == "리마인더 설정" }))
        #expect(chosen.isEmpty)
        menu.performActionForItem(at: try #require(menu.items.firstIndex { $0.title == "창 닫기" }))
        #expect(chosen == [.closeWindow])
        menu.performActionForItem(at: try #require(menu.items.firstIndex { $0.title == "노트 찾기" }))
        #expect(chosen == [.closeWindow, .findNote])
        menu.performActionForItem(at: try #require(menu.items.firstIndex { $0.title == "라이브러리" }))
        #expect(chosen == [.closeWindow, .findNote, .openLibrary])
        #expect(menu.items.allSatisfy { $0.keyEquivalent.isEmpty })
        // 구분선은 구분선 항목이고, 뒤가 비치지 않는 불투명 바탕의 뷰로 그린다.
        let separators = menu.items.filter(\.isSeparatorItem)
        #expect(separators.count == 2)
        #expect(separators.allSatisfy { $0.view is MenuSeparatorView })

        // 모두 이어져 있으면(기본) 전부 고를 수 있다.
        let all = builder.moreMenu(isPinned: false, selectedPaletteID: nil) { _ in }
        #expect(all.items.filter { !$0.isSeparatorItem && $0.action != nil && !$0.isEnabled }.isEmpty)
    }
}
