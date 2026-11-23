import AppKit
import Carbon.HIToolbox
import Models
import SwiftUI

/// 한 구획의 슬롯 높이에는 행 사이 간격과 펼친 날짜 목록이 포함된다.
package struct ReorderSection: Equatable {
    package let rows: [LibrarySelection]
    let stride: CGFloat
    let extra: [LibrarySelection: CGFloat]
    package init(_ rows: [LibrarySelection], stride: CGFloat, extra: [LibrarySelection: CGFloat] = [:]) {
        self.rows = rows
        self.stride = stride
        self.extra = extra
    }
    func height(_ row: LibrarySelection) -> CGFloat { stride + (extra[row] ?? 0) }
    func top(_ row: LibrarySelection) -> CGFloat { rows.prefix { $0 != row }.reduce(0) { $0 + height($1) } }
    package func neighbor(_ row: LibrarySelection, by step: Int) -> LibrarySelection? {
        guard let index = rows.firstIndex(of: row), rows.indices.contains(index + step) else { return nil }
        return rows[index + step]
    }
}

@MainActor @Observable package final class SidebarReorder {
    package init() {}
    private struct Drag {
        let row: LibrarySelection
        let section: ReorderSection
        let dy: CGFloat
        let target: LibrarySelection
    }
    private var drag: Drag?

    package func track(_ row: LibrarySelection, in section: ReorderSection, translation: CGFloat) {
        guard let index = section.rows.firstIndex(of: row),
              let last = section.rows.last else { return }
        let origin = section.top(row)
        let limit = section.top(last) + section.height(last) - section.height(row)
        let dy = min(max(translation, -origin), limit - origin)
        // 인접 블록의 절반을 지나면 그 블록이 비켜난다.
        var destination = index
        var distance = abs(dy)
        let step = dy < 0 ? -1 : 1
        while section.rows.indices.contains(destination + step) {
            let height = section.height(section.rows[destination + step])
            guard distance >= height / 2 else { break }
            destination += step
            distance -= height
        }
        drag = Drag(row: row, section: section, dy: dy, target: section.rows[destination])
    }

    package func offset(_ row: LibrarySelection, in section: ReorderSection) -> CGFloat {
        guard let drag, drag.section == section else { return 0 }
        if row == drag.row { return drag.dy }
        guard let index = section.rows.firstIndex(of: row),
              let from = section.rows.firstIndex(of: drag.row), let to = section.rows.firstIndex(of: drag.target) else { return 0 }
        if from < index && index <= to { return -section.height(drag.row) }
        if to <= index && index < from { return section.height(drag.row) }
        return 0
    }
    package func lifted(_ row: LibrarySelection, in section: ReorderSection) -> Bool { drag?.section == section && drag?.row == row }
    func active(in section: ReorderSection) -> Bool { drag?.section == section }
    package func cancel() { drag = nil }
    package func finish(in section: ReorderSection, move: (LibrarySelection, LibrarySelection) -> Void) {
        defer { cancel() }
        guard let drag, drag.section == section, drag.row != drag.target else { return }
        move(drag.row, drag.target)
    }
}

/// macOS가 드래그 시작에 사용하는 거리를 읽고, 움직이는 행 밖의 고정 좌표계에서 추적한다.
@MainActor package struct SidebarPan: ViewModifier {
    let row: LibrarySelection
    let section: ReorderSection
    let drag: SidebarReorder
    let move: (LibrarySelection, LibrarySelection) -> Void
    @GestureState private var tracking = false
    private static let threshold: CGFloat = {
        var size = CGSize.zero
        guard HIMouseTrackingGetParameters(OSType(kMouseParamsDragInitiation), nil, &size) == noErr else {
            return DragGesture().minimumDistance
        }
        return size.height
    }()
    package init(_ row: LibrarySelection, section: ReorderSection, drag: SidebarReorder,
                 move: @escaping (LibrarySelection, LibrarySelection) -> Void) {
        self.row = row; self.section = section; self.drag = drag; self.move = move
    }
    package func body(content: Content) -> some View {
        content.highPriorityGesture(DragGesture(minimumDistance: Self.threshold, coordinateSpace: .global)
            .updating($tracking) { _, tracking, _ in tracking = true }
            .onChanged { drag.track(row, in: section, translation: $0.translation.height) }
            .onEnded { value in
                drag.track(row, in: section, translation: value.translation.height)
                drag.finish(in: section, move: move)
            })
            .onChange(of: tracking) { _, active in
                if !active && drag.lifted(row, in: section) { drag.cancel() }
            }
            .onChange(of: section) { old, _ in
                if drag.lifted(row, in: old) { drag.cancel() }
            }
            .onDisappear { if drag.lifted(row, in: section) { drag.cancel() } }
    }
}

@MainActor package struct ReorderActions {
    let section: ReorderSection
    let row: LibrarySelection
    let move: (LibrarySelection, LibrarySelection) -> Void
    package init(_ row: LibrarySelection, section: ReorderSection, move: @escaping (LibrarySelection, LibrarySelection) -> Void) {
        self.row = row; self.section = section; self.move = move
    }
    package func available(_ step: Int) -> Bool { section.neighbor(row, by: step) != nil }
    package func perform(_ step: Int) {
        if let neighbor = section.neighbor(row, by: step) { move(row, neighbor) }
    }
    @ViewBuilder package var menu: some View {
        Button("위로", systemImage: "arrow.up") { perform(-1) }.disabled(!available(-1))
        Button("아래로", systemImage: "arrow.down") { perform(1) }.disabled(!available(1))
    }
}

extension View {
    @MainActor package func reorderAccess(_ actions: ReorderActions) -> some View {
        accessibilityActions {
            if actions.available(-1) { Button("위로") { actions.perform(-1) } }
            if actions.available(1) { Button("아래로") { actions.perform(1) } }
        }.onKeyPress(keys: [.upArrow, .downArrow]) { press in
            guard press.modifiers == .option else { return .ignored }
            actions.perform(press.key == .upArrow ? -1 : 1)
            return .handled
        }
    }

    @MainActor package func reorderPosition(_ row: LibrarySelection, in section: ReorderSection, drag: SidebarReorder,
                                            theme: Theme) -> some View {
        let dy = drag.offset(row, in: section)
        let lifted = drag.lifted(row, in: section)
        return offset(y: dy).zIndex(lifted ? 1 : 0)
            .animation(lifted || !drag.active(in: section) || NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? nil : theme.motion.animation, value: dy)
    }

    @MainActor package func reorderSurface(_ lifted: Bool, theme: Theme, radius: CGFloat) -> some View {
        background {
            if lifted {
                let layers = theme.shadow(.reorder)
                let inset = layers.map { $0.blur + abs($0.y) + abs($0.spread) }.max() ?? 0
                Canvas { context, size in
                    let row = CGRect(origin: .zero, size: size).insetBy(dx: inset, dy: inset)
                    context.withCGContext { cg in
                        for layer in layers {
                            let rect = row.insetBy(dx: -layer.spread, dy: -layer.spread)
                            let r = max(0, radius + layer.spread)
                            cg.saveGState()
                            if layer.blur > 0 {
                                cg.setShadow(offset: CGSize(width: layer.x, height: layer.y),
                                             blur: layer.blur / 2, color: layer.color.nsColor.cgColor)
                                cg.setFillColor(NSColor.black.cgColor)
                            } else {
                                cg.setFillColor(layer.color.nsColor.cgColor)
                            }
                            cg.addPath(CGPath(roundedRect: rect, cornerWidth: r, cornerHeight: r, transform: nil))
                            cg.fillPath()
                            cg.restoreGState()
                        }
                    }
                }.padding(-inset).overlay {
                    RoundedRectangle(cornerRadius: radius).fill(theme.color(.surface))
                }.allowsHitTesting(false)
            }
        }
    }
}
