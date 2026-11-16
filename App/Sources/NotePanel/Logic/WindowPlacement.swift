import CoreGraphics

/// 노트 창을 어디에 띄울지(spec 4.1, 16). 좌표는 AppKit 화면 좌표(원점이 왼쪽 아래)다.
struct WindowPlacement: Hashable {
    /// 나란히 놓는 노트 사이.
    var gap: CGFloat
    /// 자리가 겹칠 때 비켜 놓는 거리.
    var cascade: CGFloat
    /// 화면 가장자리에서 띄우는 거리.
    var margin: CGFloat

    /// 기준 노트가 없을 때: 화면 오른쪽 위. 그 자리에 이미 노트가 있으면 왼쪽 아래로 비켜 놓는다.
    func initialFrame(size: CGSize, visibleFrame: CGRect, occupied: [CGRect]) -> CGRect {
        let start = CGRect(
            x: visibleFrame.maxX - margin - size.width,
            y: visibleFrame.maxY - margin - size.height,
            width: size.width, height: size.height
        )
        return cascaded(start, visibleFrame: visibleFrame, occupied: occupied, direction: -1)
    }

    /// 새 노트는 지금 노트 옆: 위쪽을 맞춰 오른쪽에, 자리가 없으면 왼쪽에, 그것도 안 되면 비스듬히 겹쳐 놓는다.
    func frame(nextTo anchor: CGRect, size: CGSize, visibleFrame: CGRect, occupied: [CGRect]) -> CGRect {
        let y = anchor.maxY - size.height
        let right = CGRect(x: anchor.maxX + gap, y: y, width: size.width, height: size.height)
        let left = CGRect(x: anchor.minX - gap - size.width, y: y, width: size.width, height: size.height)
        for candidate in [right, left] where fitsHorizontally(candidate, in: visibleFrame)
            && !occupied.contains(where: { $0.intersects(candidate) }) {
            return clamped(candidate, to: visibleFrame)
        }
        let shifted = CGRect(x: anchor.minX + cascade, y: y - cascade, width: size.width, height: size.height)
        return cascaded(
            clamped(shifted, to: visibleFrame), visibleFrame: visibleFrame, occupied: occupied, direction: 1
        )
    }

    /// 저장해 둔 틀을 되살린다. 상단 줄(끌어 옮기는 곳)이 어느 화면에도 걸치지 않으면
    /// 그 화면이 없어진 것이므로 주 화면 안으로 옮긴다.
    func restoredFrame(saved: CGRect, screens: [CGRect], main: CGRect, handleHeight: CGFloat) -> CGRect {
        let handle = CGRect(x: saved.minX, y: saved.maxY - handleHeight, width: saved.width, height: handleHeight)
        if screens.contains(where: { $0.intersects(handle) }) { return saved }
        return clamped(saved, to: main.insetBy(dx: margin, dy: margin))
    }

    /// 틀을 영역 안으로 민다. 다 들어가지 않으면 위쪽 가장자리를 지킨다.
    func clamped(_ frame: CGRect, to area: CGRect) -> CGRect {
        var result = frame
        result.origin.x = max(area.minX, min(result.minX, area.maxX - result.width))
        result.origin.y = max(result.minY, area.minY)
        if result.maxY > area.maxY { result.origin.y = area.maxY - result.height }
        return result
    }

    private func fitsHorizontally(_ frame: CGRect, in area: CGRect) -> Bool {
        frame.minX >= area.minX && frame.maxX <= area.maxX
    }

    /// 왼쪽 위 모서리가 다른 노트와 겹치는 동안 비스듬히 옮긴다. 화면을 벗어나면 멈춘다.
    private func cascaded(
        _ start: CGRect, visibleFrame: CGRect, occupied: [CGRect], direction: CGFloat
    ) -> CGRect {
        func collides(_ candidate: CGRect) -> Bool {
            occupied.contains { abs($0.minX - candidate.minX) < 1 && abs($0.maxY - candidate.maxY) < 1 }
        }
        var frame = start
        while collides(frame) {
            let next = frame.offsetBy(dx: cascade * direction, dy: -cascade)
            guard visibleFrame.contains(next) else { break }
            frame = next
        }
        return frame
    }
}
