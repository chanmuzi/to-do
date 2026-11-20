import AppKit
import Foundation
import Testing
@testable import Theme

/// 아이콘마다의 크기 보정 표(`tokens.json`의 `iconOptical`)와 그것을 쓰는 SF Symbols 그림.
@Suite @MainActor struct SymbolScaleTests {
    @Test func bundledTableIsReadAndOnlyShrinks() throws {
        let tokens = try ThemeTokens.bundled()
        #expect(tokens.symbolScale("pin.fill") < 1)
        #expect(tokens.symbolScale("trash") < 1)
        #expect(tokens.symbolScale("xmark") < 1)
        // 메뉴 안 닫기와 더 보기 그림의 보정(D-159).
        #expect(tokens.symbolScale("xmark") == 0.85)
        #expect(tokens.symbolScale("ellipsis") == 0.85)
    }

    /// 아이콘은 예전(크기 토큰의 네모 칸에 맞춰 줄여 그림)보다 커지지 않는다: 그림의 긴 변이 칸 안에 든다.
    @Test func symbolImagesNeverOutgrowTheirSlot() throws {
        let theme = try Theme.bundled()
        let names = [
            "pin", "pin.fill", "trash", "xmark", "ellipsis", "plus", "bell", "clock", "briefcase", "house",
            "magnifyingglass", "sparkle", "drop", "eye", "eye.slash", "checkmark", "exclamationmark.triangle",
            "sidebar.left", "keyboard", "slider.horizontal.3", "apple.terminal",
        ]
        for name in names {
            for role in [ComponentToken.iconSmall, .iconMedium, .iconLarge, .menuIcon] {
                guard let image = theme.symbolImage(name, size: role) else { continue }
                #expect(max(image.size.width, image.size.height) <= theme.component(role) + 0.01, "\(name) \(role)")
            }
        }
    }

    @Test func outOfRangeScaleIsRejected() throws {
        let url = try ThemeResources.tokensURL()
        var root = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        root["iconOptical"] = ["pin": "1.2"]
        let data = try JSONSerialization.data(withJSONObject: root)
        #expect(throws: (any Error).self) { try ThemeTokens(data: data) }
    }

    @Test func symbolFrameKeepsTheSlotCentreAndAddsRoom() throws {
        let theme = try Theme.bundled()
        let frame = theme.symbolFrame(CGRect(x: 10, y: 20, width: 14, height: 14))
        #expect(frame.midX == 17 && frame.midY == 27)
        #expect(frame.width == 14 + theme.space(.sp1) * 2)
    }
}
