import CoreGraphics

/// 노트 찾기가 놓이는 자리(spec 4.1). AppKit 좌표(아래가 0)다.
nonisolated enum BrowsePlacement {
    /// 노트 창에 붙일 때 쓰는 치수.
    struct Anchor: Hashable {
        /// 노트 창의 틀.
        var frame: CGRect
        /// 노트 상단 줄의 높이.
        var chromeHeight: CGFloat
        /// 상단 줄 아래 끝과 목록 위 끝 사이의 틈.
        var gap: CGFloat
        /// 노트 오른쪽 끝에서 목록 오른쪽 끝까지 들여 놓는 거리.
        var inset: CGFloat
    }

    /// 목록 위쪽 가장자리와 왼쪽 자리. 앵커가 있으면 노트 상단 줄 아래, 없으면 화면 가운데 위쪽.
    /// 화면 밖으로 나가지 않게 안으로 밀어 넣는다. 아래로는 높이 한도만큼의 자리를 남긴다:
    /// 노트가 화면 아래쪽에 있어도 목록이 한두 줄짜리 스크롤 칸으로 찌그러지지 않고 위로 올라가 뜬다.
    static func topLeft(
        width: CGFloat, anchor: Anchor?, visibleFrame: CGRect, topRatio: Double, heightRatio: Double
    ) -> CGPoint {
        let wanted: CGPoint
        if let anchor {
            wanted = CGPoint(
                x: anchor.frame.maxX - anchor.inset - width,
                y: anchor.frame.maxY - anchor.chromeHeight - anchor.gap
            )
        } else {
            wanted = CGPoint(
                x: visibleFrame.midX - width / 2,
                y: visibleFrame.maxY - visibleFrame.height * topRatio
            )
        }
        return CGPoint(
            x: min(max(wanted.x, visibleFrame.minX), max(visibleFrame.minX, visibleFrame.maxX - width)).rounded(),
            y: min(max(wanted.y, visibleFrame.minY + visibleFrame.height * heightRatio), visibleFrame.maxY).rounded()
        )
    }

    /// 높이 한도: 화면 높이의 몫과, 위쪽 가장자리에서 화면 아래 끝까지 가운데 작은 쪽.
    static func maxHeight(top: CGFloat, visibleFrame: CGRect, heightRatio: Double) -> CGFloat {
        max(0, min(visibleFrame.height * heightRatio, top - visibleFrame.minY)).rounded(.down)
    }

    /// 위쪽 가장자리를 고정한 틀.
    static func frame(topLeft: CGPoint, width: CGFloat, height: CGFloat) -> CGRect {
        CGRect(x: topLeft.x, y: topLeft.y - height, width: width, height: height)
    }
}
