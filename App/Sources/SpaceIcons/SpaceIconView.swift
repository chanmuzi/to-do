import AppKit
import ImageIO
import SwiftUI
import Models
import Theme

/// NSImageView의 애니메이션 표현은 AppKit과 SwiftUI 양쪽에서 같은 경로를 쓴다.
public final class SpaceIconNSView: NSView {
    private let imageView = NSImageView()
    private let label = NSTextField(labelWithString: "")
    private var lastURL: URL?
    private var frames: [NSImage] = []
    private var delays: [TimeInterval] = []
    private var frameIndex = 0
    private var frameTimer: Timer?
    isolated deinit { frameTimer?.invalidate() }
    public override init(frame: NSRect) {
        super.init(frame: frame)
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.wantsLayer = true
        imageView.layer?.magnificationFilter = .nearest
        addSubview(imageView); addSubview(label)
        label.alignment = .center
    }
    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

    public func apply(_ icon: SpaceIcon, directory: URL, theme: Theme, size: CGFloat, color: NSColor? = nil,
                      symbolSize: ComponentToken? = nil) {
        imageView.isHidden = false; label.isHidden = true
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.contentTintColor = color ?? theme.nsColor(.text2)
        var url: URL?
        switch icon {
        case .none: imageView.image = nil
        case .emoji(let value):
            label.stringValue = value
            label.font = NSFont.systemFont(ofSize: size)
            label.isHidden = false; imageView.isHidden = true
        case .symbol(let name, let colorID):
            imageView.image = symbolSize.flatMap { theme.symbolImage(name, size: $0) }
                ?? NSImage(systemSymbolName: name, accessibilityDescription: name)
            if symbolSize != nil { imageView.imageScaling = .scaleNone }
            if let colorID, let tint = theme.palette.first(where: { $0.id == colorID.rawValue }) {
                imageView.contentTintColor = tint.color.nsColor
            }
        case .customSymbol(let name, let hex):
            imageView.image = symbolSize.flatMap { theme.symbolImage(name, size: $0) }
                ?? NSImage(systemSymbolName: name, accessibilityDescription: name)
            if symbolSize != nil { imageView.imageScaling = .scaleNone }
            if let rgb = UInt32(hex.trimmingCharacters(in: CharacterSet(charactersIn: "#")), radix: 16) {
                imageView.contentTintColor = NSColor(srgbRed: Double((rgb >> 16) & 255) / 255,
                    green: Double((rgb >> 8) & 255) / 255, blue: Double(rgb & 255) / 255, alpha: 1)
            }
        case .image(let name):
            url = SpaceIconAssets.url(for: name, directory: directory, dark: theme.appearance == .dark)
            if url != lastURL { loadFrames(url, fallbackDelay: theme.motion.duration) }
            imageView.contentTintColor = nil
            if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
                frameTimer?.invalidate(); frameTimer = nil; frameIndex = 0
                imageView.image = frames.first
            }
        }
        if url == nil { frameTimer?.invalidate(); frameTimer = nil; frames = []; delays = [] }
        lastURL = url
        scheduleFrame()
        needsLayout = true
    }
    private func loadFrames(_ url: URL?, fallbackDelay: TimeInterval) {
        frameTimer?.invalidate(); frameTimer = nil; frameIndex = 0
        frames = []; delays = []
        guard let url, let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            imageView.image = nil; return
        }
        for index in 0..<CGImageSourceGetCount(source) {
            guard let cg = CGImageSourceCreateImageAtIndex(source, index, nil) else { continue }
            frames.append(NSImage(cgImage: cg, size: .zero))
            let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any]
            let gif = properties?[kCGImagePropertyGIFDictionary] as? [CFString: Any]
            let delay = (gif?[kCGImagePropertyGIFUnclampedDelayTime] as? Double)
                ?? (gif?[kCGImagePropertyGIFDelayTime] as? Double) ?? fallbackDelay
            delays.append(delay > 0 ? delay : fallbackDelay)
        }
        imageView.image = frames.first
    }

    /// 이미지 자체를 프레임마다 교체하므로 화면과 앱 내부 스냅숏이 같은 프레임을 본다.
    /// Timer는 뷰를 붙잡지 않으며, 창이 닫히거나 뷰가 떨어지면 다음 틱에서 멈춘다.
    private func scheduleFrame() {
        guard frameTimer == nil, window != nil, frames.count > 1, delays[frameIndex] > 0,
              !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }
        let timer = Timer(timeInterval: delays[frameIndex], repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.frameTimer = nil
                guard self.window?.isVisible == true, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
                    self.frameIndex = 0; self.imageView.image = self.frames.first; return
                }
                self.frameIndex = (self.frameIndex + 1) % self.frames.count
                self.imageView.image = self.frames[self.frameIndex]
                self.scheduleFrame()
            }
        }
        frameTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }
    public override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        frameTimer?.invalidate(); frameTimer = nil
        scheduleFrame()
    }
    public override func layout() {
        super.layout()
        scheduleFrame()
        imageView.frame = bounds
        label.frame = NSRect(x: (bounds.width - label.intrinsicContentSize.width) / 2,
                             y: (bounds.height - label.intrinsicContentSize.height) / 2,
                             width: label.intrinsicContentSize.width, height: label.intrinsicContentSize.height)
    }
}

public struct SpaceIconView: NSViewRepresentable {
    public let icon: SpaceIcon
    public let directory: URL
    public let theme: Theme
    public let size: CGFloat
    public var color: NSColor?
    public init(icon: SpaceIcon, directory: URL, theme: Theme, size: CGFloat, color: NSColor? = nil) {
        self.icon = icon; self.directory = directory; self.theme = theme; self.size = size; self.color = color
    }
    public func makeNSView(context: Context) -> SpaceIconNSView { SpaceIconNSView(frame: .zero) }
    public func updateNSView(_ view: SpaceIconNSView, context: Context) {
        view.apply(icon, directory: directory, theme: theme, size: size, color: color)
    }
}
