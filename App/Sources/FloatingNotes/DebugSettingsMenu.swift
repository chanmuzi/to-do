#if DEBUG
import AppKit
import Theme

/// 시스템 메뉴와 그 아래의 설정 창만 같은 좌표계에 그린다.
enum DebugSettingsMenu {
    static func capture(_ menu: NSMenu, at anchor: NSView, to url: URL) {
        guard let parent = anchor.window else { return }
        let render: @MainActor () -> Void = {
            defer { menu.cancelTracking() }
            guard let popup = menu.items.compactMap({ $0.view?.window }).first,
                  let base = bitmap(parent), let overlay = bitmap(popup) else {
                AppLog.warning("설정 메뉴 창을 그릴 수 없어요")
                return
            }
            let size = parent.frame.size
            let image = NSImage(size: size)
            image.lockFocus()
            base.draw(in: NSRect(origin: .zero, size: size))
            overlay.draw(in: popup.frame.offsetBy(dx: -parent.frame.minX, dy: -parent.frame.minY))
            image.unlockFocus()
            do {
                guard let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
                      let png = rep.representation(using: .png, properties: [:]) else { throw CocoaError(.fileWriteUnknown) }
                try png.write(to: url, options: .atomic)
            } catch { AppLog.warning("설정 메뉴 그림을 저장할 수 없어요") }
        }
        let timer = Timer(timeInterval: 0.4, repeats: false) { _ in MainActor.assumeIsolated { render() } }
        RunLoop.main.add(timer, forMode: .common)
        anchor.popUpSettingsMenu(menu)
        timer.invalidate()
    }

    private static func bitmap(_ window: NSWindow) -> NSBitmapImageRep? {
        guard let view = window.contentView?.superview ?? window.contentView else { return nil }
        view.layoutSubtreeIfNeeded()
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return nil }
        view.cacheDisplay(in: view.bounds, to: rep)
        return rep
    }
}
#endif
