import CoreGraphics

/// 짧은 알림의 자리(D-041): 화면(메뉴 막대와 Dock을 뺀 영역)의 가운데 아래쪽. 영역 아래 끝에서 영역 높이의
/// `toast-bottom-screen`만큼 위에 알림의 아래쪽이 온다. 너비는 영역 안에 든다.
enum ToastPlacement {
    static func frame(size: CGSize, visibleFrame: CGRect, bottomFraction: CGFloat) -> CGRect {
        let width = min(size.width, visibleFrame.width)
        return CGRect(
            x: (visibleFrame.midX - width / 2).rounded(),
            y: (visibleFrame.minY + visibleFrame.height * bottomFraction).rounded(),
            width: width, height: size.height
        )
    }
}
