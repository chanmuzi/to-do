#!/usr/bin/env swift
// 실행: swift scripts/generate-brand-icons.swift <미리보기 폴더>
// 외부 의존성 없이 같은 도형 정의에서 SVG, PNG, 투명 구멍을 가진 벡터 PDF를 만든다.
import AppKit

struct Shape {
    let path: CGPath
    let color: String
    let svg: String
}
func rounded(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ r: CGFloat, _ color: String) -> Shape {
    Shape(path: CGPath(roundedRect: CGRect(x: x, y: y, width: w, height: h), cornerWidth: r, cornerHeight: r, transform: nil),
          color: color, svg: "<rect x=\"\(x)\" y=\"\(y)\" width=\"\(w)\" height=\"\(h)\" rx=\"\(r)\" fill=\"\(color)\"/>")
}
func stroke(_ points: [(CGFloat, CGFloat)], _ width: CGFloat, _ color: String) -> Shape {
    let line = CGMutablePath()
    line.move(to: CGPoint(x: points[0].0, y: points[0].1))
    for (x, y) in points.dropFirst() { line.addLine(to: CGPoint(x: x, y: y)) }
    let d = points.enumerated().map { "\($0.offset == 0 ? "M" : "L")\($0.element.0) \($0.element.1)" }.joined(separator: " ")
    return Shape(path: line.copy(strokingWithWidth: width, lineCap: .round, lineJoin: .round, miterLimit: 10),
                 color: color, svg: "<path d=\"\(d)\" fill=\"none\" stroke=\"\(color)\" stroke-width=\"\(width)\" stroke-linecap=\"round\" stroke-linejoin=\"round\"/>")
}
func color(_ hex: String) -> CGColor {
    let n = UInt32(hex.dropFirst(), radix: 16)!
    return CGColor(srgbRed: CGFloat((n >> 16) & 255) / 255, green: CGFloat((n >> 8) & 255) / 255,
                   blue: CGFloat(n & 255) / 255, alpha: 1)
}
let ink = "#1c1c1f", paper = "#f5f4f0"
let appShapes = [
    rounded(0, 0, 100, 100, 22, ink),
    rounded(20, 22, 60, 56, 9, paper),
    rounded(29, 33, 13, 13, 3, ink),
    stroke([(32, 39.5), (34.6, 42.1), (39.2, 37.1)], 2.6, paper),
    rounded(47, 37.5, 24, 4, 2, "#9a9a9e"),
    rounded(29, 55, 42, 4, 2, ink),
    rounded(29, 64, 26, 4, 2, ink)
]
let card = rounded(1.5, 2.5, 15, 13, 3, "#000000")
let holes = [
    stroke([(4.4, 7.2), (5.8, 8.6), (8.2, 6)], 1.4, "#000000"),
    stroke([(10, 7.3), (13.6, 7.3)], 1.4, "#000000"),
    stroke([(4.6, 11.6), (11.6, 11.6)], 1.4, "#000000")
]
let menuPath = CGMutablePath()
menuPath.addPath(card.path)
for hole in holes { menuPath.addPath(hole.path) }

func drawApp(_ context: CGContext) {
    let pixelScale = abs(context.ctm.a)
    context.saveGState()
    // Notes.app: 206px 본체 / 256px 캔버스 = 824 / 1024, 여백 100px.
    context.translateBy(x: 100, y: 100)
    context.scaleBy(x: 8.24, y: 8.24)
    for (index, shape) in appShapes.enumerated() {
        context.saveGState()
        if index == 0 {
            // Quartz의 그림자는 도형 CTM을 따르지 않으므로 출력 픽셀 배율을 직접 적용한다.
            context.setShadow(offset: CGSize(width: 0, height: -10 * pixelScale), blur: 12 * pixelScale,
                              color: CGColor(gray: 0, alpha: 0.25))
        }
        context.addPath(shape.path)
        context.setFillColor(color(shape.color))
        context.fillPath()
        context.restoreGState()
    }
    context.restoreGState()
}
func drawMenu(_ context: CGContext) {
    context.addPath(menuPath)
    context.setFillColor(CGColor(gray: 0, alpha: 1))
    context.drawPath(using: .eoFill) // 흰 잉크가 아니라 배경이 비치는 실제 구멍.
}
func png(_ url: URL, pixels: Int, canvas: CGFloat, draw: (CGContext) -> Void) throws {
    let context = CGContext(data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.translateBy(x: 0, y: CGFloat(pixels))
    context.scaleBy(x: CGFloat(pixels) / canvas, y: -CGFloat(pixels) / canvas)
    draw(context)
    let bitmap = NSBitmapImageRep(cgImage: context.makeImage()!)
    try bitmap.representation(using: .png, properties: [:])!.write(to: url)
}

guard CommandLine.arguments.count == 2 else {
    fputs("사용: swift scripts/generate-brand-icons.swift <미리보기 폴더>\n", stderr)
    exit(64)
}
let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let resources = root.appendingPathComponent("App/Resources")
let previews = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: previews, withIntermediateDirectories: true)
for size in [16, 32, 64, 128, 256, 512, 1024] {
    let url = resources.appendingPathComponent("AppIcon.appiconset/icon_\(size).png")
    try png(url, pixels: size, canvas: 1024, draw: drawApp)
    try Data(contentsOf: url).write(to: previews.appendingPathComponent("app-icon-\(size).png"))
}
let appSVG = """
<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">
  <defs><filter id="shadow" x="-20%" y="-20%" width="140%" height="150%" color-interpolation-filters="sRGB">
    <feGaussianBlur in="SourceAlpha" stdDeviation="6"/><feOffset dy="10"/>
    <feComponentTransfer><feFuncA type="linear" slope="0.25"/></feComponentTransfer>
  </filter></defs>
  <rect x="100" y="100" width="824" height="824" rx="181.28" fill="\(ink)" filter="url(#shadow)"/>
  <g transform="translate(100 100) scale(8.24)">
    \(appShapes.map(\.svg).joined(separator: "\n    "))
  </g>
</svg>
"""
try appSVG.write(to: resources.appendingPathComponent("app-icon-1024.svg"), atomically: true, encoding: .utf8)
let menuSVG = """
<svg xmlns="http://www.w3.org/2000/svg" width="18" height="18" viewBox="0 0 18 18">
  <defs><mask id="m"><rect width="18" height="18" fill="#fff"/>
    \(holes.map(\.svg).joined(separator: "\n    "))
  </mask></defs>
  \(card.svg.replacingOccurrences(of: "/>", with: " mask=\"url(#m)\"/>"))
</svg>
"""
try menuSVG.write(to: resources.appendingPathComponent("menubar-icon.svg"), atomically: true, encoding: .utf8)
var page = CGRect(x: 0, y: 0, width: 18, height: 18)
let pdf = CGContext(resources.appendingPathComponent("menubar-icon.pdf") as CFURL, mediaBox: &page, nil)!
pdf.beginPDFPage(nil)
pdf.translateBy(x: 0, y: 18)
pdf.scaleBy(x: 1, y: -1)
drawMenu(pdf)
pdf.endPDFPage()
pdf.closePDF()
// 최종 PDF를 다시 읽어서 1x/2x PNG로 검증한다.
let document = CGPDFDocument(resources.appendingPathComponent("menubar-icon.pdf") as CFURL)!
for scale in [1, 2] {
    try png(previews.appendingPathComponent("menubar-\(scale)x.png"), pixels: 18 * scale, canvas: 18) { context in
        context.translateBy(x: 0, y: 18)
        context.scaleBy(x: 1, y: -1)
        context.drawPDFPage(document.page(at: 1)!)
    }
}
print("Generated C2 SVG, 7 app PNGs, 18pt vector PDF and previews: \(previews.path)")
