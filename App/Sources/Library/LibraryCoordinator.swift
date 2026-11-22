import AppKit
import SwiftUI
import Models
import Routing
import Store
import Theme

/// App만 이 객체를 조립한다. 노트를 열고 옮기는 요청은 Core Routing으로 돌아간다.
public final class LibraryCoordinator: NSObject, NSWindowDelegate {
    public let model: LibraryModel
    public private(set) var window: NSWindow?
    private var spacePopover: NSPopover?
    public var allowsKeyWindows = true
    public var beforeMove: () -> Void = {}
    private var timer: Timer?
    public init(theme: Theme, notes: any NoteStoring, spaces: SpaceStore, windows: WindowStateStore,
                preferences: LibraryPreferencesStore, router: any Routing) {
        model = LibraryModel(theme: theme, notes: notes, spaces: spaces, windows: windows, preferences: preferences, router: router)
        super.init()
    }
    public func show() {
        model.opened()
        if window == nil {
            let theme = model.theme
            let window = LibraryWindow(contentRect: NSRect(x: 0, y: 0, width: theme.component(.libraryWidth), height: theme.component(.libraryHeight)),
                styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
            window.allowsKey = allowsKeyWindows
            window.handleContentClick = { [weak model] point in
                guard let model else { return }
                let insideDetail = [model.upcomingSourceView, model.upcomingDetailView].compactMap { $0 }.contains {
                    $0.bounds.contains($0.convert(point, from: nil))
                }
                if !insideDetail {
                    model.dismissUpcoming()
                }
                guard model.editingSpace else { return }
                if let view = model.spaceInputView, view.bounds.contains(view.convert(point, from: nil)) { return }
                model.cancelSpaceEditing()
            }
            window.title = "라이브러리"; window.titleVisibility = .hidden; window.titlebarAppearsTransparent = true
            window.isReleasedWhenClosed = false; window.delegate = self
            window.minSize = NSSize(width: theme.component(.libraryMinWidth), height: theme.component(.libraryMinHeight))
            let content = LibraryHostingView(rootView: LibraryRootView(model: model))
            window.contentView = content
            window.initialFirstResponder = content
            window.defaultButtonCell = nil
            window.backgroundColor = theme.nsColor(.surface)
            window.center()
            if !allowsKeyWindows, let screen = NSScreen.screens.last {
                window.setFrameOrigin(screen.visibleFrame.origin)
            }
            self.window = window
        }
        orderLibraryFront()
        timer?.invalidate()
        // 자정과 리마인더가 지나면 열린 라이브러리의 분류도 갱신한다.
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.model.refreshCalendar() }
        }
    }
    /// 앱 전환은 사용자가 보고 있던 구획과 선택을 보존한다.
    public func bringForward() {
        if let window, window.isVisible || window.isMiniaturized {
            if window.isMiniaturized { window.deminiaturize(nil) }
            orderLibraryFront()
        } else {
            show()
        }
    }

    private func orderLibraryFront() {
        if allowsKeyWindows {
            window?.makeKeyAndOrderFront(nil)
            window?.makeMain()
        } else {
            window?.orderFront(nil)
        }
    }
    #if DEBUG
    public func importImageForVerification(_ url: URL, space: SpaceID) { model.importImage(url, for: space) }
    public func expandSpaceForVerification(_ id: SpaceID) { model.expanded.insert(id) }
    public func snapshotIconPicker(space: SpaceID, tab: Int? = nil, to url: URL) throws {
        let view = LibraryHostingView(rootView: IconPickerView(model: model, spaceID: space, initialTab: tab))
        view.frame = NSRect(origin: .zero, size: view.fittingSize)
        view.layoutSubtreeIfNeeded()
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        guard let data = rep.representation(using: .png, properties: [:]) else { return }
        try data.write(to: url)
    }
    #endif
    public func close() { model.cancelSpaceEditing(); spacePopover?.close(); window?.close(); timer?.invalidate(); timer = nil }
    public func windowDidResignKey(_ notification: Notification) {
        model.dismissUpcoming()
        if !model.choosingDraftIcon { model.cancelSpaceEditing() }
    }
    public func windowWillClose(_ notification: Notification) { model.dismissUpcoming(); timer?.invalidate(); timer = nil }
    public func showSpacePicker(for id: NoteID, anchor: NSView?) {
        beforeMove()
        guard let anchor = anchor ?? window?.contentView else { show(); showSpacePicker(for: id, anchor: window?.contentView); return }
        let popover = NSPopover(); popover.behavior = .transient
        popover.contentViewController = NSHostingController(rootView: SpacePickerView(model: model, noteID: id) { [weak popover] in popover?.close() })
        spacePopover = popover
        popover.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: .maxY)
    }
}

private final class LibraryWindow: NSWindow {
    var allowsKey = true
    var handleContentClick: (NSPoint) -> Void = { _ in }
    private weak var pressedRow: LibraryRowInputView?
    override func sendEvent(_ event: NSEvent) {
        // 노트 창과 같은 경로: hosting view의 제스처 처리 전에 줄이 누름/뗌 한 쌍을 소유한다.
        // 특히 두 번째 누름이 SwiftUI 부모에 흡수되어 더블 클릭이 없어지지 않게 한다.
        switch event.type {
        case .leftMouseDown:
            handleContentClick(event.locationInWindow)
            pressedRow = nil
            if let content = contentView, let parent = content.superview,
               let row = content.hitTest(parent.convert(event.locationInWindow, from: nil)) as? LibraryRowInputView {
                pressedRow = row
                if allowsKey, !isKeyWindow { makeKeyAndOrderFront(nil) }
                row.mouseDown(with: event)
                return
            }
        case .leftMouseUp:
            if let row = pressedRow, row.window === self {
                pressedRow = nil
                row.mouseUp(with: event)
                return
            }
            pressedRow = nil
        case .leftMouseDragged:
            if pressedRow != nil { return }
        default: break
        }
        super.sendEvent(event)
    }
    override var canBecomeKey: Bool { allowsKey }
    override var canBecomeMain: Bool { allowsKey }
}

private struct SpacePickerView: View {
    @Bindable var model: LibraryModel
    let noteID: NoteID
    let dismiss: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: model.theme.space(.sp1)) {
            Text("스페이스 옮기기").font(model.theme.font(.row))
            choice("스페이스 없음", id: nil)
            ForEach(model.spaceList) { space in choice(space.name, id: space.id) }
            if let error = model.error { Text(error).font(model.theme.font(.rowSub)) }
        }.focusEffectDisabled().buttonStyle(LibraryButtonStyle(theme: model.theme)).font(model.theme.font(.body))
            .padding(model.theme.space(.sp3)).frame(width: model.theme.component(.iconPickerWidth))
            .onExitCommand(perform: dismiss)
    }
    private func choice(_ title: String, id: SpaceID?) -> some View {
        let selected = model.index.notes.first { $0.id == noteID }?.spaceID == id
        return Button { move(id) } label: {
            HStack(spacing: model.theme.space(.sp2)) {
                Image(systemName: "checkmark").opacity(selected ? 1 : 0)
                    .frame(width: model.theme.component(.menuCheckColumn)).accessibilityHidden(true)
                Text(title)
                Spacer()
            }.frame(height: model.theme.component(.rowHeight)).contentShape(Rectangle())
        }.accessibilityAddTraits(selected ? .isSelected : [])
    }
    private func move(_ id: SpaceID?) {
        do { try model.move(noteID, to: id); dismiss() } catch { model.error = error.localizedDescription }
    }
}
