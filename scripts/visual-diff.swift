// Compares two folders of PNG snapshots pixel by pixel and reports what changed.
//
//   swift scripts/visual-diff.swift <before-folder> <after-folder> [diff-output-folder]
//
// For every PNG present in both folders it prints the share of pixels that differ
// (any channel by more than 2/255) and the bounding box of the change. With an output
// folder it also writes <name>-diff.png: the "after" image dimmed, changed pixels in red.
// Exits 1 when anything differs, so it can gate a script.

import AppKit

struct Bitmap {
    let width: Int
    let height: Int
    let pixels: [UInt8]  // RGBA8, premultiplied, top-left origin

    init?(url: URL) {
        guard let image = NSImage(contentsOf: url),
              let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let (w, h) = (cg.width, cg.height)
        var buffer = [UInt8](repeating: 0, count: w * h * 4)
        let drawn = buffer.withUnsafeMutableBytes { raw -> Bool in
            guard let context = CGContext(data: raw.baseAddress, width: w, height: h, bitsPerComponent: 8,
                                          bytesPerRow: w * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        guard drawn else { return nil }
        (width, height, pixels) = (w, h, buffer)
    }
}

let arguments = CommandLine.arguments.dropFirst().map { URL(fileURLWithPath: $0) }
guard arguments.count >= 2 else {
    FileHandle.standardError.write("usage: visual-diff.swift <before> <after> [diff-output]\n".data(using: .utf8)!)
    exit(2)
}
let (before, after) = (arguments[0], arguments[1])
let output = arguments.count > 2 ? arguments[2] : nil
if let output { try? FileManager.default.createDirectory(at: output, withIntermediateDirectories: true) }

let names = Set((try? FileManager.default.contentsOfDirectory(atPath: before.path)) ?? [])
    .intersection((try? FileManager.default.contentsOfDirectory(atPath: after.path)) ?? [])
    .filter { $0.hasSuffix(".png") }
    .sorted()

var changed = 0
for name in names {
    guard let a = Bitmap(url: before.appendingPathComponent(name)),
          let b = Bitmap(url: after.appendingPathComponent(name)) else {
        print("?  \(name): unreadable")
        changed += 1
        continue
    }
    guard a.width == b.width, a.height == b.height else {
        print("≠  \(name): size \(a.width)×\(a.height) → \(b.width)×\(b.height)")
        changed += 1
        continue
    }
    var count = 0
    var box = (minX: Int.max, minY: Int.max, maxX: -1, maxY: -1)
    var mask = [Bool](repeating: false, count: a.width * a.height)
    for i in 0..<(a.width * a.height) {
        let o = i * 4
        if abs(Int(a.pixels[o]) - Int(b.pixels[o])) > 2 || abs(Int(a.pixels[o + 1]) - Int(b.pixels[o + 1])) > 2
            || abs(Int(a.pixels[o + 2]) - Int(b.pixels[o + 2])) > 2 || abs(Int(a.pixels[o + 3]) - Int(b.pixels[o + 3])) > 2 {
            count += 1
            mask[i] = true
            let (x, y) = (i % a.width, i / a.width)
            box = (min(box.minX, x), min(box.minY, y), max(box.maxX, x), max(box.maxY, y))
        }
    }
    if count == 0 {
        print("=  \(name)")
        continue
    }
    changed += 1
    let share = Double(count) / Double(a.width * a.height) * 100
    print(String(format: "≠  %@: %.2f%% of pixels, in x %d–%d, y %d–%d", name, share, box.minX, box.maxX, box.minY, box.maxY))

    if let output {
        var pixels = b.pixels
        for i in 0..<(b.width * b.height) {
            let o = i * 4
            if mask[i] {
                pixels[o] = 255; pixels[o + 1] = 0; pixels[o + 2] = 0; pixels[o + 3] = 255
            } else {
                for c in 0..<3 { pixels[o + c] = UInt8(Int(pixels[o + c]) / 4 + 191 * Int(pixels[o + 3]) / 255) }
            }
        }
        let rep = pixels.withUnsafeMutableBytes { raw -> NSBitmapImageRep? in
            var plane: UnsafeMutablePointer<UInt8>? = raw.baseAddress?.assumingMemoryBound(to: UInt8.self)
            return NSBitmapImageRep(bitmapDataPlanes: &plane, pixelsWide: b.width, pixelsHigh: b.height, bitsPerSample: 8,
                                    samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                    bytesPerRow: b.width * 4, bitsPerPixel: 32)?.copy() as? NSBitmapImageRep
        }
        let url = output.appendingPathComponent(name.replacingOccurrences(of: ".png", with: "-diff.png"))
        try? rep?.representation(using: .png, properties: [:])?.write(to: url)
    }
}

let missing = Set((try? FileManager.default.contentsOfDirectory(atPath: before.path)) ?? []).filter { $0.hasSuffix(".png") }
    .symmetricDifference(Set((try? FileManager.default.contentsOfDirectory(atPath: after.path)) ?? []).filter { $0.hasSuffix(".png") })
for name in missing.sorted() { print("±  \(name): only in one folder") }

let total = changed + missing.count
print(total == 0 ? "no changes in \(names.count) images" : "\(total) of \(names.count + missing.count) images changed")
exit(changed + missing.count == 0 ? 0 : 1)
