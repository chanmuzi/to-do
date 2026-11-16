import AppKit

/// 메뉴 막대 아이콘을 켜고 끄는 곳. 아이콘 그림은 켤 때 처음 읽는다.
///
/// 아이콘은 없어도 되는 것이다(같은 항목이 앱 메뉴와 Dock 메뉴에 있다). 그래서 그림 파일을 읽지 못해도
/// 앱을 멈추지 않고, 경고를 남긴 채 메뉴 막대 아이콘 없이 간다. 꺼 둔 동안에는 파일을 읽지도 않는다.
final class MenuBarIconSwitch<Item> {
    private let loadIcon: () throws -> NSImage
    private let makeItem: (NSImage) -> Item
    private let warn: (String) -> Void
    /// 메뉴 막대에 놓인 것. 꺼 두었거나 그림을 읽지 못했으면 `nil`.
    private(set) var item: Item?

    init(
        loadIcon: @escaping () throws -> NSImage, makeItem: @escaping (NSImage) -> Item,
        warn: @escaping (String) -> Void
    ) {
        self.loadIcon = loadIcon
        self.makeItem = makeItem
        self.warn = warn
    }

    func apply(shown: Bool) {
        guard shown else {
            item = nil
            return
        }
        guard item == nil else { return }
        do {
            item = makeItem(try loadIcon())
        } catch {
            warn("메뉴 막대 아이콘을 띄우지 못했습니다. 아이콘 없이 계속합니다: \(error)")
        }
    }
}
