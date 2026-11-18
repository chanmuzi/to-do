// Float 최종 아이콘 자산 생성기 (3차 1안 "종이 노트 창"을 벡터로 다시 그림).
// 사용: swift scripts/generate-brand-icons.swift <출력 폴더>
// 그림 좌표는 타일 한 변 824 단위, 왼쪽 위 원점. 레거시 .icns는 1024 캔버스에 100 여백으로,
// Icon Composer 겹은 타일이 1024 전체를 채우게(시스템이 둥근 네모를 씌움) 그린다.
import AppKit
import CoreGraphics

let T: CGFloat = 824
let srgb = CGColorSpace(name: CGColorSpace.sRGB)!

func hex(_ s: String, _ a: CGFloat = 1) -> CGColor {
    let n = UInt32(s.dropFirst(), radix: 16)!
    return CGColor(colorSpace: srgb, components: [CGFloat((n >> 16) & 255) / 255, CGFloat((n >> 8) & 255) / 255, CGFloat(n & 255) / 255, a])!
}
func gradient(_ stops: [(CGColor, CGFloat)]) -> CGGradient {
    CGGradient(colorsSpace: srgb, colors: stops.map { $0.0 } as CFArray, locations: stops.map { $0.1 })!
}

struct Palette {
    let bgTop, bgBottom: String
    let bgLight: CGFloat
    let barTop, barBottom: String
    let bodyTop, bodyBottom, edge: String
    let pin, line1, line2: String
    let shadow: CGFloat
}
let light = Palette(bgTop: "#F9F5EF", bgBottom: "#EAE2D7", bgLight: 0.55,
                    barTop: "#3C3B3E", barBottom: "#1E1E20",
                    bodyTop: "#FFFFFF", bodyBottom: "#F2EFEA", edge: "#D8D3CB",
                    pin: "#F4F2EE", line1: "#D3CFC9", line2: "#E1DDD7", shadow: 0.26)
let dark = Palette(bgTop: "#38373B", bgBottom: "#1B1B1D", bgLight: 0.12,
                   barTop: "#66625D", barBottom: "#4A4642",
                   bodyTop: "#EFECE6", bodyBottom: "#DCD8D1", edge: "#8E8981",
                   pin: "#F4F2EE", line1: "#BDB8B1", line2: "#CBC7C0", shadow: 0.6)

// 노트 창 치수 (타일 단위)
let win = CGRect(x: 162, y: 196, width: 500, height: 400)
let winR: CGFloat = 44

func roundedPath(_ r: CGRect, _ radius: CGFloat) -> CGPath { CGPath(roundedRect: r, cornerWidth: radius, cornerHeight: radius, transform: nil) }

// 배경: 위에서 아래로 옅어지는 상아색, 위쪽 가운데 부드러운 빛, 위 가장자리 광택.
func drawBackground(_ c: CGContext, _ p: Palette, rim: Bool) {
    c.saveGState()
    c.drawLinearGradient(gradient([(hex(p.bgTop), 0), (hex(p.bgBottom), 1)]), start: CGPoint(x: 0, y: 0), end: CGPoint(x: 0, y: T), options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    c.drawRadialGradient(gradient([(hex("#FFFFFF", p.bgLight), 0), (hex("#FFFFFF", 0), 1)]), startCenter: CGPoint(x: T / 2, y: T * 0.18), startRadius: 0, endCenter: CGPoint(x: T / 2, y: T * 0.18), endRadius: T * 0.62, options: [])
    if rim {
        c.drawLinearGradient(gradient([(hex("#FFFFFF", p.bgLight * 0.9), 0), (hex("#FFFFFF", 0), 1)]), start: CGPoint(x: 0, y: 0), end: CGPoint(x: 0, y: T * 0.08), options: [])
    }
    c.restoreGState()
}

// 그림자: 노트 아래 떨어진 곳에 넓고 흐린 타원과 좁고 진한 타원.
func drawShadow(_ c: CGContext, _ p: Palette, pixelScale: CGFloat) {
    func blurred(_ rect: CGRect, alpha: CGFloat, blur: CGFloat) {
        c.saveGState()
        let off: CGFloat = 4000
        // 도형은 화면 밖(위)에 그리고 그림자만 제자리로 내린다. 그림자 offset은 장치 좌표(위가 +)라 배율을 직접 곱한다.
        c.setShadow(offset: CGSize(width: 0, height: -off * pixelScale), blur: blur * pixelScale, color: hex("#000000", alpha))
        c.addEllipse(in: rect.offsetBy(dx: 0, dy: -off))
        c.setFillColor(hex("#000000", 1))
        c.fillPath()
        c.restoreGState()
    }
    blurred(CGRect(x: 412 - 235, y: 640, width: 470, height: 64), alpha: p.shadow * 0.75, blur: 34)
    blurred(CGRect(x: 412 - 190, y: 652, width: 380, height: 26), alpha: p.shadow * 0.55, blur: 12)
}

// 노트 창: 두께 띠, 본문, 검은 제목 줄, 핀 점, 글 줄 두 개, 가장자리 선.
func drawNote(_ c: CGContext, _ p: Palette, simple: Bool) {
    let barH: CGFloat = simple ? 118 : 92
    // 두께 (아래로 비치는 얇은 판)
    c.addPath(roundedPath(win.offsetBy(dx: 0, dy: simple ? 0 : 7), winR))
    c.setFillColor(hex(p.edge))
    c.fillPath()
    c.saveGState()
    c.addPath(roundedPath(win, winR))
    c.clip()
    c.drawLinearGradient(gradient([(hex(p.bodyTop), 0), (hex(p.bodyBottom), 1)]), start: CGPoint(x: 0, y: win.minY), end: CGPoint(x: 0, y: win.maxY), options: [])
    // 제목 줄
    let bar = CGRect(x: win.minX, y: win.minY, width: win.width, height: barH)
    c.saveGState()
    c.clip(to: bar)
    c.drawLinearGradient(gradient([(hex(p.barTop), 0), (hex(p.barBottom), 1)]), start: CGPoint(x: 0, y: bar.minY), end: CGPoint(x: 0, y: bar.maxY), options: [])
    c.drawLinearGradient(gradient([(hex("#FFFFFF", 0.16), 0), (hex("#FFFFFF", 0), 1)]), start: CGPoint(x: 0, y: bar.minY), end: CGPoint(x: 0, y: bar.minY + 18), options: [])
    c.restoreGState()
    c.setFillColor(hex("#000000", 0.18))
    c.fill(CGRect(x: win.minX, y: bar.maxY, width: win.width, height: 2))
    if !simple {
        c.addPath(roundedPath(CGRect(x: win.minX + 64, y: bar.maxY + 86, width: 332, height: 24), 12))
        c.setFillColor(hex(p.line1)); c.fillPath()
        c.addPath(roundedPath(CGRect(x: win.minX + 64, y: bar.maxY + 148, width: 250, height: 24), 12))
        c.setFillColor(hex(p.line2)); c.fillPath()
    }
    c.restoreGState()
    // 핀 점
    let pinR: CGFloat = simple ? 20 : 15
    let pin = CGRect(x: win.maxX - 58 - pinR, y: win.minY + barH / 2 - pinR, width: pinR * 2, height: pinR * 2)
    c.saveGState()
    c.addEllipse(in: pin); c.clip()
    c.drawLinearGradient(gradient([(hex(p.pin), 0), (hex("#D6D2CB"), 1)]), start: CGPoint(x: 0, y: pin.minY), end: CGPoint(x: 0, y: pin.maxY), options: [])
    c.restoreGState()
    // 가장자리
    c.addPath(roundedPath(win.insetBy(dx: 1, dy: 1), winR - 1))
    c.setStrokeColor(hex("#000000", 0.08)); c.setLineWidth(2); c.strokePath()
}

enum Layer { case background, shadow, note, composite }

// 레거시 .icns: 1024 캔버스, 824 둥근 타일(반지름 185), 타일 그림자 포함.
func drawLegacy(_ c: CGContext, _ p: Palette, pixelScale: CGFloat, simple: Bool) {
    c.saveGState()
    c.translateBy(x: 100, y: 100)
    let tile = roundedPath(CGRect(x: 0, y: 0, width: T, height: T), 185)
    c.saveGState()
    c.setShadow(offset: CGSize(width: 0, height: -10 * pixelScale), blur: 14 * pixelScale, color: hex("#000000", 0.22))
    c.addPath(tile); c.setFillColor(hex(p.bgBottom)); c.fillPath()
    c.restoreGState()
    c.addPath(tile); c.clip()
    drawBackground(c, p, rim: true)
    drawShadow(c, p, pixelScale: pixelScale)
    drawNote(c, p, simple: simple)
    // 유리 테두리: 안쪽 흰 띠(위가 더 밝음)와 바깥 머리카락 선
    c.saveGState()
    c.addPath(roundedPath(CGRect(x: 5, y: 5, width: T - 10, height: T - 10), 180))
    c.setLineWidth(10); c.replacePathWithStrokedPath(); c.clip()
    c.drawLinearGradient(gradient([(hex("#FFFFFF", p.bgLight * 1.6), 0), (hex("#FFFFFF", p.bgLight * 0.6), 1)]), start: .zero, end: CGPoint(x: 0, y: T), options: [])
    c.restoreGState()
    c.addPath(roundedPath(CGRect(x: 0.75, y: 0.75, width: T - 1.5, height: T - 1.5), 184.25))
    c.setStrokeColor(hex("#000000", 0.07)); c.setLineWidth(1.5); c.strokePath()
    c.restoreGState()
}

// Icon Composer 겹: 타일이 1024 전체. 배경은 꽉 찬 사각형(시스템이 모양을 씌움).
func drawLayer(_ c: CGContext, _ p: Palette, _ layer: Layer, pixelScale: CGFloat) {
    c.saveGState()
    c.scaleBy(x: 1024 / T, y: 1024 / T)
    let s = pixelScale * 1024 / T
    switch layer {
    case .background: drawBackground(c, p, rim: false)
    case .shadow: drawShadow(c, p, pixelScale: s)
    case .note: drawNote(c, p, simple: false)
    case .composite: drawBackground(c, p, rim: false); drawShadow(c, p, pixelScale: s); drawNote(c, p, simple: false)
    }
    c.restoreGState()
}

func png(_ url: URL, pixels: Int, canvas: CGFloat = 1024, draw: (CGContext, CGFloat) -> Void) throws {
    let c = CGContext(data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0, space: srgb,
                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    c.interpolationQuality = .high
    c.translateBy(x: 0, y: CGFloat(pixels))
    c.scaleBy(x: CGFloat(pixels) / canvas, y: -CGFloat(pixels) / canvas)
    draw(c, CGFloat(pixels) / canvas)
    let rep = NSBitmapImageRep(cgImage: c.makeImage()!)
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try rep.representation(using: .png, properties: [:])!.write(to: url)
}

// 메뉴 막대: 2차 1안. 18pt 캔버스, 그림 16pt, 선 1.5.
func drawMenu(_ c: CGContext) {
    c.setStrokeColor(hex("#000000")); c.setLineWidth(1.5); c.setLineCap(.round); c.setLineJoin(.round)
    c.addPath(roundedPath(CGRect(x: 1.75, y: 1.75, width: 14.5, height: 14.5), 3)); c.strokePath()
    c.move(to: CGPoint(x: 5.25, y: 10.75)); c.addLine(to: CGPoint(x: 10.75, y: 10.75)); c.strokePath()
    let head = CGMutablePath()
    head.move(to: CGPoint(x: 4.75, y: 1.75)); head.addLine(to: CGPoint(x: 13.25, y: 1.75))
    head.addArc(tangent1End: CGPoint(x: 16.25, y: 1.75), tangent2End: CGPoint(x: 16.25, y: 4.75), radius: 3)
    head.addLine(to: CGPoint(x: 16.25, y: 6.5)); head.addLine(to: CGPoint(x: 1.75, y: 6.5)); head.addLine(to: CGPoint(x: 1.75, y: 4.75))
    head.addArc(tangent1End: CGPoint(x: 1.75, y: 1.75), tangent2End: CGPoint(x: 4.75, y: 1.75), radius: 3)
    head.closeSubpath()
    c.addPath(head); c.setFillColor(hex("#000000")); c.fillPath()
}

guard CommandLine.arguments.count == 2 else {
    fputs("사용: swift scripts/generate-brand-icons.swift <미리보기 폴더>\n", stderr)
    exit(64)
}
let out = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let resources = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("App/Resources")
for (name, palette) in [("light", light), ("dark", dark)] {
    for (layer, file) in [(Layer.background, "1-background"), (.shadow, "2-shadow"), (.note, "3-note-window")] {
        try png(resources.appendingPathComponent("AppIcon.icon/Assets/\(name)-\(file).png"), pixels: 1024) { c, scale in
            drawLayer(c, palette, layer, pixelScale: scale)
        }
    }
}
for pixels in [16, 32, 64, 128, 256, 512, 1024] {
    let url = resources.appendingPathComponent("AppIcon.appiconset/icon_\(pixels).png")
    try png(url, pixels: pixels) { c, scale in drawLegacy(c, light, pixelScale: scale, simple: pixels <= 32) }
    try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
    try Data(contentsOf: url).write(to: out.appendingPathComponent("app-icon-\(pixels).png"))
}
let menuSVG = """
<svg xmlns="http://www.w3.org/2000/svg" width="18" height="18" viewBox="0 0 18 18">
  <g fill="none" stroke="#000000" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round">
    <rect x="1.75" y="1.75" width="14.5" height="14.5" rx="3"/>
    <path d="M5.25 10.75h5.5"/>
  </g>
  <path d="M4.75 1.75h8.5a3 3 0 0 1 3 3v1.75h-14.5v-1.75a3 3 0 0 1 3-3z" fill="#000000"/>
</svg>
"""
try (menuSVG + "\n").write(to: resources.appendingPathComponent("menubar-icon.svg"), atomically: true, encoding: .utf8)
var page = CGRect(x: 0, y: 0, width: 18, height: 18)
let pdfURL = resources.appendingPathComponent("menubar-icon.pdf")
let pdf = CGContext(pdfURL as CFURL, mediaBox: &page, nil)!
pdf.beginPDFPage(nil); pdf.translateBy(x: 0, y: 18); pdf.scaleBy(x: 1, y: -1); drawMenu(pdf); pdf.endPDFPage(); pdf.closePDF()
let doc = CGPDFDocument(pdfURL as CFURL)!
for k in [1, 2] {
    try png(out.appendingPathComponent("menubar-\(k)x.png"), pixels: 18 * k, canvas: 18) { c, _ in
        c.translateBy(x: 0, y: 18); c.scaleBy(x: 1, y: -1); c.drawPDFPage(doc.page(at: 1)!)
    }
}
print("done: \(out.path)")
