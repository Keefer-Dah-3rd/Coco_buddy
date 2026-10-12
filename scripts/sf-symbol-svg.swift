// Extracts SF Symbols as 16 × 16 SVG outlines for the Figma icon set.
//
//   swift scripts/sf-symbol-svg.swift play.fill xmark calendar > icons.json
//
// Figma can't render SF Symbols, so icons go in as vectors. The SF Pro font installed with
// Apple's fonts (developer.apple.com/fonts) holds every symbol as a glyph in the private-use
// area, but its glyph names are codepoints. So each symbol is rendered by AppKit, compared
// with every SF Pro symbol glyph, and the best shape match is written out at Semibold, 11 pt,
// centred in 16 × 16. The score is printed to stderr; above ~0.08 check the match by eye.

import AppKit
import CoreText

let grid = 28

/// A shape drawn large, cropped to its ink and scaled into grid × grid, plus its aspect ratio.
func fingerprint(_ draw: (CGContext) -> Bool) -> [Float]? {
    let size = 128
    guard let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: size,
                              space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return nil }
    ctx.setFillColor(gray: 0, alpha: 1)
    ctx.fill(CGRect(x: 0, y: 0, width: size, height: size))
    guard draw(ctx), let image = ctx.makeImage(), let data = ctx.data?.assumingMemoryBound(to: UInt8.self) else { return nil }
    var (minX, minY, maxX, maxY) = (size, size, -1, -1)
    for y in 0..<size { for x in 0..<size where data[y * size + x] > 40 { minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y) } }
    guard maxX >= minX else { return nil }
    let (w, h) = (maxX - minX + 1, maxY - minY + 1)
    let side = max(w, h)
    guard let crop = image.cropping(to: CGRect(x: minX - (side - w) / 2, y: minY - (side - h) / 2, width: side, height: side)),
          let small = CGContext(data: nil, width: grid, height: grid, bitsPerComponent: 8, bytesPerRow: grid,
                                space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return nil }
    small.interpolationQuality = .high
    small.draw(crop, in: CGRect(x: 0, y: 0, width: grid, height: grid))
    let pixels = small.data!.assumingMemoryBound(to: UInt8.self)
    return (0..<(grid * grid)).map { Float(pixels[$0]) / 255 } + [Float(w) / Float(h)]
}

func distance(_ a: [Float], _ b: [Float]) -> Float {
    var d: Float = 0
    for i in 0..<(grid * grid) { d += abs(a[i] - b[i]) }
    return d / Float(grid * grid) + abs(log(a[grid * grid] / b[grid * grid])) * 0.5
}

func glyph(_ font: CTFont, _ scalar: UInt32) -> CGGlyph? {
    var utf16 = Array(String(Character(Unicode.Scalar(scalar)!)).utf16)
    var glyphs = [CGGlyph](repeating: 0, count: utf16.count)
    return CTFontGetGlyphsForCharacters(font, &utf16, &glyphs, utf16.count) && glyphs[0] != 0 ? glyphs[0] : nil
}

let matchFont = CTFontCreateWithName("SF Pro" as CFString, 96, nil)
let outlineFont = CTFontCreateWithName("SF Pro Text Semibold" as CFString, 11, nil)
var candidates: [(UInt32, [Float])] = []
for scalar in UInt32(0x100000)..<0x101400 {
    guard let g = glyph(matchFont, scalar), let path = CTFontCreatePathForGlyph(matchFont, g, nil) else { continue }
    if let print = fingerprint({ ctx in
        let box = path.boundingBox
        ctx.translateBy(x: 64 - box.midX, y: 64 - box.midY)
        ctx.addPath(path); ctx.setFillColor(gray: 1, alpha: 1); ctx.fillPath()
        return true
    }) { candidates.append((scalar, print)) }
}
guard !candidates.isEmpty else {
    FileHandle.standardError.write("SF Pro with symbols isn't installed — get it from developer.apple.com/fonts\n".data(using: .utf8)!)
    exit(1)
}

func n(_ v: CGFloat) -> String { let t = String(format: "%.2f", v); return t.hasSuffix(".00") ? String(t.dropLast(3)) : t }

var out: [String: String] = [:]
for name in CommandLine.arguments.dropFirst() {
    guard let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
        .withSymbolConfiguration(.init(pointSize: 80, weight: .regular)),
          let target = fingerprint({ ctx in
              var rect = CGRect(x: 64 - image.size.width / 2, y: 64 - image.size.height / 2, width: image.size.width, height: image.size.height)
              guard let cg = image.cgImage(forProposedRect: &rect, context: nil, hints: nil) else { return false }
              ctx.clip(to: rect, mask: cg); ctx.setFillColor(gray: 1, alpha: 1); ctx.fill(rect)
              return true
          }) else {
        FileHandle.standardError.write("\(name): not an SF Symbol on this Mac\n".data(using: .utf8)!)
        continue
    }
    let best = candidates.map { ($0.0, distance($0.1, target)) }.min { $0.1 < $1.1 }!
    FileHandle.standardError.write(String(format: "%@ → U+%X, score %.3f\n", name, best.0, best.1).data(using: .utf8)!)
    guard let g = glyph(outlineFont, best.0), let path = CTFontCreatePathForGlyph(outlineFont, g, nil) else { continue }
    let box = path.boundingBox
    let (dx, dy) = (8 - box.midX, 8 + box.midY)  // centre in 16 × 16; font space is y-up
    var d = ""
    path.applyWithBlock { element in
        let e = element.pointee
        func p(_ i: Int) -> String { "\(n(e.points[i].x + dx)) \(n(dy - e.points[i].y))" }
        switch e.type {
        case .moveToPoint: d += "M\(p(0))"
        case .addLineToPoint: d += "L\(p(0))"
        case .addQuadCurveToPoint: d += "Q\(p(0)) \(p(1))"
        case .addCurveToPoint: d += "C\(p(0)) \(p(1)) \(p(2))"
        case .closeSubpath: d += "Z"
        @unknown default: break
        }
    }
    out[name] = ##"<svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 16 16"><path d="\##(d)" fill="#000"/></svg>"##
}
let json = try! JSONSerialization.data(withJSONObject: out, options: [.sortedKeys, .prettyPrinted])
print(String(data: json, encoding: .utf8)!)
