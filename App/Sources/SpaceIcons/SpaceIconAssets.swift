import AppKit
import ImageIO
import Models
import Theme
import UniformTypeIdentifiers

public enum SpaceIconAssets {
    public static let builtins = ["terminal", "computer", "keyboard", "mouse"]
    public static func url(for name: String, directory: URL, dark: Bool = false) -> URL? {
        guard name == URL(fileURLWithPath: name).lastPathComponent, !name.contains("..") else { return nil }
        if builtins.contains(name) {
            let filename = name + (dark ? "-dark" : "") + ".gif"
            let bundled = Bundle.main.resourceURL?.appendingPathComponent("SpaceImages/" + filename)
            if let bundled, FileManager.default.fileExists(atPath: bundled.path) { return bundled }
            return Bundle.module.resourceURL?.appendingPathComponent("SpaceImages/" + filename)
        }
        let url = directory.appendingPathComponent(name)
        let resolved = url.resolvingSymlinksInPath()
        guard resolved.deletingLastPathComponent() == directory.resolvingSymlinksInPath() else { return nil }
        return url
    }

    public enum ImportError: LocalizedError {
        case unsupported, tooLarge, unreadable, writeFailed
        public var errorDescription: String? {
            switch self {
            case .unsupported: "PNG, SVG, GIF 파일을 골라 주세요."
            case .tooLarge: "GIF는 1MB 이하만 올릴 수 있습니다."
            case .unreadable: "이미지를 읽을 수 없습니다."
            case .writeFailed: "이미지를 저장하지 못했습니다."
            }
        }
    }

    /// 사용자가 고른 파일을 복사해 보관한다. PNG/SVG는 PNG, GIF는 프레임 지연을 보존하고 계속 반복하는 GIF로 줄인다.
    public static func importFile(_ source: URL, directory: URL, maxPixels: Int) throws -> String {
        let ext = source.pathExtension.lowercased()
        guard ["png", "svg", "gif"].contains(ext) else { throw ImportError.unsupported }
        let scoped = source.startAccessingSecurityScopedResource()
        defer { if scoped { source.stopAccessingSecurityScopedResource() } }
        let data = try Data(contentsOf: source)
        if ext == "gif", data.count > 1_048_576 { throw ImportError.tooLarge }
        let output = NSMutableData()
        if ext == "svg" {
            guard let image = NSImage(data: data) else { throw ImportError.unreadable }
            let scale = min(1, CGFloat(maxPixels) / max(image.size.width, image.size.height))
            let size = NSSize(width: max(1, image.size.width * scale), height: max(1, image.size.height * scale))
            let resized = NSImage(size: size, flipped: false) { rect in
                image.draw(in: rect); return true
            }
            guard let tiff = resized.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
                  let png = rep.representation(using: .png, properties: [:]) else { throw ImportError.unreadable }
            output.append(png)
        } else {
            guard let input = CGImageSourceCreateWithData(data as CFData, nil) else { throw ImportError.unreadable }
            let count = ext == "gif" ? CGImageSourceGetCount(input) : 1
            guard count > 0, let destination = CGImageDestinationCreateWithData(
                output, (ext == "gif" ? UTType.gif : .png).identifier as CFString, count, nil
            ) else { throw ImportError.unreadable }
            if ext == "gif" {
                CGImageDestinationSetProperties(destination, [kCGImagePropertyGIFDictionary:
                    [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
            }
            for index in 0..<count {
                guard let frame = CGImageSourceCreateThumbnailAtIndex(input, index, [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceThumbnailMaxPixelSize: maxPixels,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                ] as CFDictionary) else { throw ImportError.unreadable }
                CGImageDestinationAddImage(destination, frame, CGImageSourceCopyPropertiesAtIndex(input, index, nil))
            }
            guard CGImageDestinationFinalize(destination) else { throw ImportError.writeFailed }
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let name = UUID().uuidString.lowercased() + (ext == "gif" ? ".gif" : ".png")
        try (output as Data).write(to: directory.appendingPathComponent(name), options: .atomic)
        return name
    }
}
