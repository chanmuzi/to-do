import AppKit

extension Theme {
    /// SF Symbols 아이콘(spec 18.2). 모든 화면이 이 한 곳에서 같은 설정(굵기 regular, 크기 토큰)으로 만든다.
    ///
    /// 크기는 예전과 같거나 작다. 예전에는 크기 토큰의 점 크기로 만든 그림을 그 크기의 네모 칸에 맞춰 줄여
    /// 그렸다(`.scaleProportionallyDown`). 여기서는 그 줄인 값(칸 안에 드는 크기, 1 이하)을 점 크기에 미리 곱하고,
    /// 눈으로 커 보이는 아이콘(채운 핀 등)만 보정 표(`tokens.json`의 `iconOptical`, 1 이하)로 한 번 더 줄인다.
    /// 그리는 쪽은 그림을 늘리거나 줄이지 않고 제 크기 그대로 자리 가운데에 둔다
    /// (`NSImageView.imageScaling = .scaleNone`). 같은 줄의 아이콘은 같은 가운데 선에 놓인다.
    public func symbolImage(_ name: String, size: ComponentToken) -> NSImage? {
        let slot = component(size)
        func image(pointSize: CGFloat) -> NSImage? {
            NSImage(systemSymbolName: name, accessibilityDescription: nil)?.withSymbolConfiguration(
                NSImage.SymbolConfiguration(pointSize: pointSize, weight: .regular, scale: .medium)
            )
        }
        // 그림의 여백은 점 크기에 꼭 비례하지 않는다. 긴 변이 칸에 들 때까지 몇 번 좁혀 맞춘다.
        var pointSize = slot
        guard var fitted = image(pointSize: pointSize) else { return nil }
        for _ in 0..<4 {
            let longest = max(fitted.size.width, fitted.size.height)
            guard longest > slot else { break }
            pointSize *= slot / longest
            guard let next = image(pointSize: pointSize) else { return nil }
            fitted = next
        }
        let scale = tokens.symbolScale(name)
        guard scale < 1 else { return fitted }
        return image(pointSize: pointSize * scale) ?? fitted
    }

    /// `symbolImage`를 그림 크기 그대로(`.scaleNone`) 둘 이미지 뷰의 틀. 아이콘 자리(`slot`)와 가운데가 같고
    /// 사방으로 `sp-1`만큼 넓혀 그림이 잘리지 않게 한다. 다른 요소의 자리는 `slot`으로 잰다.
    public func symbolFrame(_ slot: CGRect) -> CGRect {
        let side = max(slot.width, slot.height) + space(.sp1) * 2
        return CGRect(x: slot.midX - side / 2, y: slot.midY - side / 2, width: side, height: side)
    }
}
