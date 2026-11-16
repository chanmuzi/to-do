import CoreGraphics

/// 캡처 바가 놓이는 자리(spec 4.1): 화면 가운데 아래쪽. AppKit 좌표(아래가 0)다.
nonisolated enum CapturePlacement {
    /// - Parameters:
    ///   - visibleFrame: 바를 띄울 화면에서 메뉴 막대와 Dock을 뺀 영역.
    ///   - bottomRatio: 영역 아래 끝에서 바 아래쪽까지의 거리가 영역 높이에서 차지하는 몫.
    static func frame(size: CGSize, visibleFrame: CGRect, bottomRatio: Double) -> CGRect {
        let width = min(size.width, visibleFrame.width)
        let wanted = visibleFrame.minY + (visibleFrame.height * bottomRatio).rounded()
        // 낮은 화면에서도 바가 영역 위로 나가지 않는다.
        let y = max(visibleFrame.minY, min(wanted, visibleFrame.maxY - size.height))
        return CGRect(
            x: (visibleFrame.midX - width / 2).rounded(), y: y, width: width, height: size.height
        )
    }
}
