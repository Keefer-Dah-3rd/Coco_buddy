#if DEBUG
import AppKit
import ImageIO
import UniformTypeIdentifiers
import BuddyCharacter

/// Renders the running Coco for review: every facing, the gallop, and animations of her
/// running, turning and dashing. Debug builds only:
///
///     DesktopBuddy.app/Contents/MacOS/DesktopBuddy --run-preview ~/Desktop/coco-run
enum RunPreview {
    static func run(into folder: URL) {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let t0 = 800_000_000.0
        write(directionsSheet(t: t0), to: folder.appendingPathComponent("run-directions.png"))
        write(gallopSheet(t: t0), to: folder.appendingPathComponent("run-gallop.png"))
        write(heroSheet(t: t0), to: folder.appendingPathComponent("run-hero.png"))
        writeGIF(runningInPlace(t: t0), delay: 1.0 / 30, to: folder.appendingPathComponent("run-cycle.gif"))
        let turning = turningAround(t: t0)
        writeGIF(turning, delay: 1.0 / 30, to: folder.appendingPathComponent("run-turning.gif"))
        write(strip(of: turning, every: 3, columns: 10), to: folder.appendingPathComponent("run-turning-frames.png"))
        let dash = dashAcross(t: t0)
        writeGIF(dash.frames, delay: 1.0 / 30, to: folder.appendingPathComponent("run-dash.gif"))
        write(dash.strip, to: folder.appendingPathComponent("run-dash-frames.png"))
    }

    // MARK: - Sheets

    /// All 32 facings, mid-stride, with an arrow for the direction she's travelling on screen.
    static func directionsSheet(t: TimeInterval) -> NSImage {
        let stage = Stage(columns: 8, rows: 4)
        for k in 0..<Dash.facings {
            let angle = Double(k) * 2 * .pi / Double(Dash.facings)
            let facing = SIMD2(cos(angle), sin(angle))
            stage.tiles[k].art.render(CharacterAnimator.runningPose(facing: facing, strides: 0.3, effort: 1, at: t),
                                      focusProgress: nil)
        }
        let image = stage.snapshot()
        return annotate(image, stage: stage) { k in
            let angle = Double(k) * 2 * .pi / Double(Dash.facings)
            let screen = SIMD2(cos(angle), sin(angle) * sin(Dash.viewElevation))
            return ("\(k) · \(String(format: "%.2f", Double(k) * 11.25))°", screen)
        }
    }

    /// Eight moments of one stride, in four directions.
    static func gallopSheet(t: TimeInterval) -> NSImage {
        let facings = [0.0, -45.0, 90.0, -90.0].map { SIMD2(cos($0 * .pi / 180), sin($0 * .pi / 180)) }
        let stage = Stage(columns: 8, rows: facings.count)
        for (row, facing) in facings.enumerated() {
            for column in 0..<8 {
                stage.tiles[row * 8 + column].art.render(
                    CharacterAnimator.runningPose(facing: facing, strides: Double(column) / 8, effort: 1, at: t + Double(column) / 44),
                    focusProgress: nil)
            }
        }
        return stage.snapshot()
    }

    /// Five key views, large: side, three-quarter front, front, three-quarter back, back.
    static func heroSheet(t: TimeInterval) -> NSImage {
        let angles = [0.0, -45.0, -90.0, 135.0, 90.0]
        let stage = Stage(columns: angles.count, rows: 2, tile: NSSize(width: 300, height: 280), scale: 2.4)
        for (index, angle) in angles.enumerated() {
            let facing = SIMD2(cos(angle * .pi / 180), sin(angle * .pi / 180))
            // Top row: stretched out in flight. Bottom row: gathered, legs underneath.
            stage.tiles[index].art.render(CharacterAnimator.runningPose(facing: facing, strides: 0.3, effort: 1, at: t),
                                          focusProgress: nil)
            stage.tiles[angles.count + index].art.render(CharacterAnimator.runningPose(facing: facing, strides: 0.8, effort: 1, at: t + 0.1),
                                                         focusProgress: nil)
        }
        return stage.snapshot()
    }

    // MARK: - Animations

    /// Four directions galloping in place for two seconds.
    static func runningInPlace(t: TimeInterval) -> [CGImage] {
        let facings = [0.0, -45.0, 135.0, -90.0].map { SIMD2(cos($0 * .pi / 180), sin($0 * .pi / 180)) }
        let stage = Stage(columns: facings.count, rows: 1)
        return (0..<60).compactMap { frame in
            let time = Double(frame) / 30
            for (index, facing) in facings.enumerated() {
                stage.tiles[index].art.render(
                    CharacterAnimator.runningPose(facing: facing, strides: time * Dash.topCadence, effort: 1, at: t + time),
                    focusProgress: nil)
            }
            return stage.snapshot().cgImage
        }
    }

    /// Galloping while turning all the way round through the 32 facings, each step
    /// blended into the next exactly as a curving run does it.
    static func turningAround(t: TimeInterval) -> [CGImage] {
        let stage = Stage(columns: 1, rows: 1, tile: NSSize(width: 220, height: 200), scale: 1.5)
        return (0..<150).compactMap { frame in
            let time = Double(frame) / 30
            var sum = SIMD2<Double>.zero
            for k in 0..<6 {
                // A facing that sweeps evenly once round in five seconds, starting toward
                // the viewer, snapped to the 32 facings as a run would be.
                let a = 2 * .pi * (time - 0.1 * Double(k) / 5) / 5 - .pi / 2
                sum += Dash.facing(forScreenDirection: SIMD2(cos(a), sin(a) * sin(Dash.viewElevation)))
            }
            let facing = sum / (sum.x * sum.x + sum.y * sum.y).squareRoot()
            stage.tiles[0].art.render(CharacterAnimator.runningPose(facing: facing, strides: time * 4.5, effort: 0.8, at: t + time),
                                      focusProgress: nil)
            return stage.snapshot().cgImage
        }
    }

    /// The whole call on a small desktop: wind-up, dash, a change of course, and sitting down.
    /// Also returns every third frame cropped around her, as a filmstrip.
    static func dashAcross(t: TimeInterval) -> (frames: [CGImage], strip: NSImage) {
        let size = NSSize(width: 720, height: 420)
        let desk = NSView(frame: NSRect(origin: .zero, size: size))
        desk.wantsLayer = true
        desk.layer?.backgroundColor = NSColor(hex: 0xD9E0E6).cgColor
        let artSize = NSSize(width: 96, height: 114)
        let art = CocoLayerView(frame: NSRect(origin: .zero, size: artSize))
        desk.addSubview(art)
        let window = offscreenWindow(for: desk)
        defer { window.orderOut(nil) }

        // Paws are 7% up the art box: keep that point on the dash.
        let pawOffset = CGPoint(x: artSize.width / 2, y: artSize.width * 0.07)
        var animator = CharacterAnimator()
        let first = Dash(from: SIMD2(600, 60), to: SIMD2(120, 260), at: t)
        animator.setDash(first)
        let turnAt = first.launchTime + 0.55
        var redirected = false
        var images: [CGImage] = []
        var crops: [CGImage] = []
        var time = t - 0.3
        while time < t + 6 {
            if !redirected, time >= turnAt {
                animator.setDash(first.redirected(to: SIMD2(560, 250), at: time))
                redirected = true
            }
            let dash = animator.dash ?? first
            let paws = dash.position(at: time)
            art.frame.origin = CGPoint(x: paws.x - pawOffset.x, y: paws.y - pawOffset.y)
            art.render(animator.pose(at: time), focusProgress: nil)
            if let image = snapshot(desk) {
                if images.count % 3 == 0 {
                    // Pixels per point, and CGImage rows run top-down.
                    let scale = CGFloat(image.width) / size.width
                    let box = CGRect(x: art.frame.midX - 75, y: size.height - art.frame.minY - 140, width: 150, height: 150)
                    if let crop = image.cropping(to: CGRect(x: box.minX * scale, y: box.minY * scale,
                                                            width: box.width * scale, height: box.height * scale)) {
                        crops.append(crop)
                    }
                }
                images.append(image)
            }
            if time > dash.endTime + 0.6 { break }
            time += 1.0 / 30
        }
        let columns = 8
        let rows = (crops.count + columns - 1) / columns
        let strip = NSImage(size: NSSize(width: 150 * columns, height: 150 * rows), flipped: true) { _ in
            for (index, crop) in crops.enumerated() {
                let rect = NSRect(x: 150 * (index % columns), y: 150 * (index / columns), width: 150, height: 150)
                NSImage(cgImage: crop, size: rect.size).draw(in: rect)
                ("\(index * 3)" as NSString).draw(at: NSPoint(x: rect.minX + 4, y: rect.minY + 2), withAttributes: [
                    .font: NSFont.monospacedSystemFont(ofSize: 9, weight: .medium), .foregroundColor: NSColor.gray,
                ])
            }
            return true
        }
        return (images, strip)
    }

    /// Every nth frame of an animation, tiled, numbered.
    static func strip(of frames: [CGImage], every n: Int, columns: Int) -> NSImage {
        let picked = stride(from: 0, to: frames.count, by: n).map { frames[$0] }
        guard let first = picked.first else { return NSImage() }
        let scale = CGFloat(first.width) / 220
        let tile = NSSize(width: CGFloat(first.width) / scale / 1.6, height: CGFloat(first.height) / scale / 1.6)
        let rows = (picked.count + columns - 1) / columns
        return NSImage(size: NSSize(width: tile.width * CGFloat(columns), height: tile.height * CGFloat(rows)), flipped: true) { _ in
            for (index, frame) in picked.enumerated() {
                let rect = NSRect(x: tile.width * CGFloat(index % columns), y: tile.height * CGFloat(index / columns),
                                  width: tile.width, height: tile.height)
                NSImage(cgImage: frame, size: rect.size).draw(in: rect)
                ("\(index * n)" as NSString).draw(at: NSPoint(x: rect.minX + 3, y: rect.minY + 2), withAttributes: [
                    .font: NSFont.monospacedSystemFont(ofSize: 8, weight: .medium), .foregroundColor: NSColor.gray,
                ])
            }
            return true
        }
    }

    // MARK: - Rendering

    /// A grid of art views in an offscreen window.
    final class Stage {
        struct Tile { let art: CocoLayerView; let frame: NSRect }
        let container: NSView
        let tiles: [Tile]
        let tileSize: NSSize
        let columns: Int
        let rows: Int
        private let window: NSWindow

        init(columns: Int, rows: Int, tile: NSSize = NSSize(width: 150, height: 140), scale: CGFloat = 1) {
            self.columns = columns
            self.rows = rows
            tileSize = tile
            container = NSView(frame: NSRect(x: 0, y: 0, width: tile.width * CGFloat(columns), height: tile.height * CGFloat(rows)))
            container.wantsLayer = true
            container.layer?.backgroundColor = NSColor(hex: 0xD9E0E6).cgColor
            var tiles: [Tile] = []
            for index in 0..<(columns * rows) {
                let column = index % columns
                let row = index / columns
                let frame = NSRect(x: CGFloat(column) * tile.width, y: CGFloat(rows - 1 - row) * tile.height,
                                   width: tile.width, height: tile.height)
                let width = 96 * scale
                let art = CocoLayerView(frame: NSRect(x: frame.midX - width / 2, y: frame.minY + 14,
                                                      width: width, height: width + 18 * scale))
                container.addSubview(art)
                tiles.append(Tile(art: art, frame: frame))
            }
            self.tiles = tiles
            window = RunPreview.offscreenWindow(for: container)
        }

        func snapshot() -> NSImage {
            let image = NSImage(size: container.bounds.size)
            if let cg = RunPreview.snapshot(container) {
                image.addRepresentation(NSBitmapImageRep(cgImage: cg))
            }
            return image
        }

        deinit { MainActor.assumeIsolated { window.orderOut(nil) } }
    }

    static func offscreenWindow(for view: NSView) -> NSWindow {
        let window = NSWindow(contentRect: NSRect(origin: NSPoint(x: -20_000, y: -20_000), size: view.frame.size),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView = view
        window.orderFrontRegardless()
        view.layoutSubtreeIfNeeded()
        return window
    }

    static func snapshot(_ view: NSView) -> CGImage? {
        view.layoutSubtreeIfNeeded()
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return nil }
        view.cacheDisplay(in: view.bounds, to: rep)
        return rep.cgImage
    }

    /// Labels each tile with its facing and an arrow for its direction of travel on screen.
    static func annotate(_ image: NSImage, stage: Stage, label: @escaping (Int) -> (String, SIMD2<Double>)) -> NSImage {
        NSImage(size: image.size, flipped: false) { rect in
            image.draw(in: rect)
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.monospacedSystemFont(ofSize: 10, weight: .medium),
                .foregroundColor: NSColor(hex: 0x4A4542),
            ]
            for (index, tile) in stage.tiles.enumerated() {
                let (text, direction) = label(index)
                (text as NSString).draw(at: NSPoint(x: tile.frame.minX + 8, y: tile.frame.minY + 4), withAttributes: attributes)
                let length = (direction.x * direction.x + direction.y * direction.y).squareRoot()
                guard length > 0 else { continue }
                let center = NSPoint(x: tile.frame.maxX - 20, y: tile.frame.maxY - 20)
                let tip = NSPoint(x: center.x + direction.x / length * 12, y: center.y + direction.y / length * 12)
                let tail = NSPoint(x: center.x - direction.x / length * 12, y: center.y - direction.y / length * 12)
                let arrow = NSBezierPath()
                arrow.move(to: tail)
                arrow.line(to: tip)
                let back = atan2(direction.y, direction.x) + .pi
                for spread in [-0.5, 0.5] {
                    arrow.move(to: tip)
                    arrow.line(to: NSPoint(x: tip.x + cos(back + spread) * 5, y: tip.y + sin(back + spread) * 5))
                }
                arrow.lineWidth = 1.5
                arrow.lineCapStyle = .round
                BrandPalette.accent.setStroke()
                arrow.stroke()
            }
            return true
        }
    }

    private static func write(_ image: NSImage, to url: URL) {
        guard let tiff = image.tiffRepresentation,
              let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else { return }
        try? png.write(to: url)
    }

    private static func writeGIF(_ frames: [CGImage], delay: Double, to url: URL) {
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.gif.identifier as CFString, frames.count, nil) else { return }
        CGImageDestinationSetProperties(destination, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
        let frameProperties = [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: delay,
                                                               kCGImagePropertyGIFUnclampedDelayTime: delay]] as CFDictionary
        for frame in frames {
            CGImageDestinationAddImage(destination, frame, frameProperties)
        }
        CGImageDestinationFinalize(destination)
        print("run preview: \(url.lastPathComponent) — \(frames.count) frames")
    }
}

private extension NSImage {
    var cgImage: CGImage? { cgImage(forProposedRect: nil, context: nil, hints: nil) }
}
#endif
