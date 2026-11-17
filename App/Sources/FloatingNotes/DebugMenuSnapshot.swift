#if DEBUG
import AppKit

/// 시스템 메뉴의 스크롤/창 재사용과 무관하게 실제 메뉴 행을 빠짐없이 그린다.
enum DebugMenuSnapshot {
    static func write(_ menu: NSMenu, to url: URL) throws {
        let rows = menu.items.compactMap(\.view)
        // NSMenuItem은 자신이 가진 뷰의 원점을 0으로 되돌린다. 확인용 메뉴에서만 소유를 분리한다.
        menu.items.forEach { $0.view = nil }
        let width = max(menu.minimumWidth, rows.map(\.frame.width).max() ?? 0)
        let height = rows.reduce(CGFloat.zero) { $0 + $1.frame.height }
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: width, height: height),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        guard let container = window.contentView else { window.close(); throw CocoaError(.fileWriteUnknown) }
        container.wantsLayer = true
        var top = height
        for row in rows {
            top -= row.frame.height
            let rowHeight = row.frame.height
            container.addSubview(row)
            row.frame = NSRect(x: 0, y: top, width: width, height: rowHeight)
        }
        if let screen = NSScreen.screens.last { window.setFrameOrigin(screen.visibleFrame.origin) }
        // 키 창으로 만들지 않는다. AppKit이 메뉴 행의 backing store를 그린 다음 캡처한다.
        window.orderFront(nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [menu] in
            defer { window.close() }
            _ = menu
            container.layoutSubtreeIfNeeded()
            window.displayIfNeeded()
            do {
                try DebugViewAudit.write(container, to: url.appendingPathExtension("views.json"))
                let rowsInfo = rows.map { ["class": String(describing: type(of: $0)), "frame": NSStringFromRect($0.frame), "hidden": String($0.isHidden), "attached": String($0.superview === container)] }
                try JSONSerialization.data(withJSONObject: rowsInfo, options: .prettyPrinted).write(to: url.appendingPathExtension("json"))
                guard let bitmap = container.bitmapImageRepForCachingDisplay(in: container.bounds) else { throw CocoaError(.fileWriteUnknown) }
                container.cacheDisplay(in: container.bounds, to: bitmap)
                guard let png = bitmap.representation(using: .png, properties: [:]) else { throw CocoaError(.fileWriteUnknown) }
                try png.write(to: url, options: .atomic)
            } catch { AppLog.warning("메뉴 행을 그리지 못했습니다: \(error)") }
        }
    }
}
#endif
