#if DEBUG
import AppKit
import SwiftUI
import BuddyCore

/// Stills of the illustrated banners for design QA and the Figma library (Debug only):
///
///     Coco.app/Contents/MacOS/Coco --banner-snapshots ~/Desktop/coco-banners
///
/// Writes, per banner: every light × weather as the finished card (`cards/<banner>/…png`) and
/// as a contact sheet (`sheet-<banner>.png`); the bare art at 640 × 304 px for comparing with
/// the Make file's own render (`art/<banner>/<time>-<weather>.png`); the card with 0, 1, 2, 3,
/// 5, 8, 10, 14 and 31 tasks (`tasks-<banner>.png`); and SVG of the art (`svg/…`), which is what
/// the Figma library imports. Run an unsandboxed build.
enum BannerSnapshots {
    static let cardWidth: CGFloat = 350
    static let taskCounts = [0, 1, 2, 3, 5, 8, 10, 14, 31]

    static func run(into folder: URL) {
        let fm = FileManager.default
        try? fm.createDirectory(at: folder, withIntermediateDirectories: true)
        for banner in BannerID.allCases {
            let cards = folder.appendingPathComponent("cards/\(banner.rawValue)")
            let art = folder.appendingPathComponent("art/\(banner.rawValue)")
            let svg = folder.appendingPathComponent("svg/\(banner.rawValue)")
            let figma = folder.appendingPathComponent("figma/\(banner.rawValue)")
            for dir in [cards, art, svg, figma] { try? fm.createDirectory(at: dir, withIntermediateDirectories: true) }
            var sheet: [[NSImage]] = []
            for time in BannerTimeOfDay.allCases {
                var row: [NSImage] = []
                for weather in BannerWeather.allCases {
                    let state = BannerState(banner: banner, time: time, weather: weather, progress: .init(done: 2, total: 5))
                    let name = "\(time.rawValue)-\(weather.rawValue)"
                    let card = render(card(state, caption: BannerCaption(weather: weather.label.uppercased())))
                    write(card, to: cards.appendingPathComponent("\(name).png"))
                    row.append(card)
                    write(renderArt(state), to: art.appendingPathComponent("\(name).png"))
                    try? BannerArt.document(state).svg.write(to: svg.appendingPathComponent("\(name).svg"), atomically: true, encoding: .utf8)
                    try? BannerArt.document(state).figmaSVG(name: "\(banner.rawValue) · \(time.label) · \(weather.label)")
                        .write(to: figma.appendingPathComponent("\(name).svg"), atomically: true, encoding: .utf8)
                }
                sheet.append(row)
            }
            write(grid(sheet, gap: 12), to: folder.appendingPathComponent("sheet-\(banner.rawValue).png"))
            let counts = taskCounts.map { total in
                render(card(BannerState(banner: banner, time: .daytime, weather: .sunny,
                                        progress: .init(done: (total + 1) / 2, total: total)),
                            caption: BannerCaption(weather: "SUNNY")))
            }
            write(grid([Array(counts.prefix(5)), Array(counts.dropFirst(5))], gap: 12),
                  to: folder.appendingPathComponent("tasks-\(banner.rawValue).png"))
        }
        // Progress steps for one banner, to check sliding endpoints and lit slots.
        for banner in [BannerID.cornerBookshop, .laundryInTheSky, .quietCarriage, .slowFerry] {
            let steps = (0...5).map { done in
                render(card(BannerState(banner: banner, time: .evening, weather: .cloudy, progress: .init(done: done, total: 5)),
                            caption: BannerCaption(weather: "CLOUDY")))
            }
            write(grid([Array(steps.prefix(3)), Array(steps.dropFirst(3))], gap: 12),
                  to: folder.appendingPathComponent("progress-\(banner.rawValue).png"))
        }
        // Other widths: the art and text scale together, keeping the composition.
        let wide = BannerState(banner: .laundryInTheSky, time: .evening, weather: .windy, progress: .init(done: 6, total: 8))
        write(grid([[280, 350, 480].map { width in
            render(IllustratedBannerView(state: wide, caption: BannerCaption(weather: "WINDY · 61°"), animated: false)
                .frame(width: width).padding(10).background(Color.white))
        }], gap: 12), to: folder.appendingPathComponent("widths.png"))
        // The corner states: loading, stale and no weather.
        let base = BannerState(banner: .windowNook, time: .morning, weather: .sunny, progress: .init(done: 1, total: 4))
        write(grid([[
            render(card(base, caption: BannerCaption())),
            render(card(base, caption: BannerCaption(isLoading: true))),
            render(card(BannerState(banner: .windowNook, time: .morning, weather: .rainy, progress: base.progress),
                        caption: BannerCaption(weather: "RAIN · 11°", isStale: true))),
        ]], gap: 12), to: folder.appendingPathComponent("captions.png"))
    }

    private static func card(_ state: BannerState, caption: BannerCaption) -> some View {
        IllustratedBannerView(state: state, caption: caption, animated: false)
            .frame(width: cardWidth)
            .padding(10)
            .background(Color.white)
    }

    /// A SwiftUI card through a real offscreen window at 2×.
    private static func render<Content: View>(_ content: Content) -> NSImage {
        let hosting = NSHostingView(rootView: content)
        hosting.frame.size = hosting.fittingSize
        let window = NSWindow(contentRect: NSRect(origin: NSPoint(x: -20_000, y: -20_000), size: hosting.frame.size),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView = hosting
        window.orderFrontRegardless()
        hosting.layoutSubtreeIfNeeded()
        for scene in hosting.descendants(of: BannerSceneView.self) {
            scene.renderScale = 2
            scene.staticOnly = true
            scene.needsLayout = true
        }
        RunLoop.main.run(until: Date().addingTimeInterval(0.25))
        let image = capture(hosting)
        window.orderOut(nil)
        return image
    }

    /// Only the art, 320 pt wide at 2× (640 × 304 px) — the size the Make file's SVG is compared at.
    private static func renderArt(_ state: BannerState) -> NSImage {
        let view = BannerSceneView(frame: NSRect(x: 0, y: 0, width: 320, height: 152))
        view.renderScale = 2
        view.staticOnly = true
        let window = NSWindow(contentRect: NSRect(x: -20_000, y: -20_000, width: 320, height: 152),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView = view
        window.orderFrontRegardless()
        view.show(state, animated: false)
        view.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        let image = capture(view)
        window.orderOut(nil)
        return image
    }

    private static func capture(_ view: NSView) -> NSImage {
        let size = view.bounds.size
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * 2), pixelsHigh: Int(size.height * 2),
                                   bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                   colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        rep.size = size
        view.cacheDisplay(in: view.bounds, to: rep)
        let image = NSImage(size: size)
        image.addRepresentation(rep)
        return image
    }

    private static func grid(_ rows: [[NSImage]], gap: CGFloat) -> NSImage {
        let cell = rows.flatMap { $0 }.reduce(NSSize.zero) { NSSize(width: max($0.width, $1.size.width), height: max($0.height, $1.size.height)) }
        let columns = rows.map(\.count).max() ?? 1
        let size = NSSize(width: CGFloat(columns) * cell.width + CGFloat(columns + 1) * gap,
                          height: CGFloat(rows.count) * cell.height + CGFloat(rows.count + 1) * gap)
        return NSImage(size: size, flipped: true) { _ in
            NSColor(hex: 0xECEEF1).setFill()
            NSRect(origin: .zero, size: size).fill()
            for (r, row) in rows.enumerated() {
                for (c, image) in row.enumerated() {
                    image.draw(in: NSRect(x: gap + CGFloat(c) * (cell.width + gap), y: gap + CGFloat(r) * (cell.height + gap),
                                          width: image.size.width, height: image.size.height),
                               from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
                }
            }
            return true
        }
    }

    private static func write(_ image: NSImage, to url: URL) {
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: [.ctm: AffineTransform(scale: 2)]) else { return }
        let rep = NSBitmapImageRep(cgImage: cg)
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
    }
}

extension NSView {
    func descendants<T: NSView>(of type: T.Type) -> [T] {
        subviews.flatMap { ($0 as? T).map { [$0] } ?? [] } + subviews.flatMap { $0.descendants(of: type) }
    }
}
#endif
