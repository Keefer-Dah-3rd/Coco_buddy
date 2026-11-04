import AppKit
import QuartzCore
import BuddyCore

/// Turns a banner frame (`SceneDocument`) into Core Animation layers, with SVG's rules: fills
/// and strokes inherit down groups (fill defaults to black, stroke to none), `opacity` belongs to
/// one element, `clip-path` clips in the element's own space, gradients fill the shape's
/// bounding box, and the dot pattern tiles from the origin.
///
/// Every path is built straight into points at the banner's size, so line art is drawn as
/// vectors at the screen's resolution — never a scaled bitmap — and stroke weights scale exactly
/// with the art. The layers that move (clouds, rain, the ferry, the thumb…) come back in
/// `movers` with the pivot their CSS animation used, for `BannerMotion` to animate.
struct BannerLayerBuilder {
    /// Points per scene unit (the art is 320 units wide).
    let scale: CGFloat
    let document: SceneDocument

    struct Mover {
        let motion: BannerArt.Motion
        let layer: CALayer
        /// The point (in banner points) rotations and scales turn about.
        let pivot: CGPoint
        /// The progress-driven horizontal offset, in points (thumb and ferry only).
        let offsetX: CGFloat
    }

    struct Result {
        let root: CALayer
        let movers: [Mover]
        /// The done-fill bar of the rail (anchored at its left end), for sliding its width.
        let railFill: CALayer?
    }

    /// Inherited presentation attributes.
    private struct Style {
        var fill: String? = "#000000"
        var stroke: String? = nil
        var strokeWidth: CGFloat = 1
        var lineCap: CAShapeLayerLineCap = .butt
        var lineJoin: CAShapeLayerLineJoin = .miter
        var fillOpacity: CGFloat = 1
        var dash: [CGFloat]? = nil

        mutating func apply(_ node: SceneNode) {
            if let v = node["fill"] { fill = v == "none" ? nil : v }
            if let v = node["stroke"] { stroke = v == "none" ? nil : v }
            if let v = node["stroke-width"], let n = Double(v) { strokeWidth = n }
            if let v = node["stroke-linecap"] { lineCap = v == "round" ? .round : v == "square" ? .square : .butt }
            if let v = node["stroke-linejoin"] { lineJoin = v == "round" ? .round : v == "bevel" ? .bevel : .miter }
            if let v = node["fill-opacity"], let n = Double(v) { fillOpacity = n }
            if let v = node["stroke-dasharray"] {
                dash = v.split(whereSeparator: { $0 == " " || $0 == "," }).compactMap { Double($0) }.map { CGFloat($0) }
            }
        }
    }

    private var movers: [Mover] = []
    private var railFill: CALayer?
    private let size: CGSize

    init(document: SceneDocument, width: CGFloat) {
        self.document = document
        scale = width / SceneDocument.viewBox.width
        size = CGSize(width: width, height: SceneDocument.viewBox.height * scale)
    }

    /// Scene units → points, y down (the host view is flipped).
    private var base: CGAffineTransform {
        CGAffineTransform(scaleX: scale, y: scale)
            .translatedBy(x: -SceneDocument.viewBox.x, y: -SceneDocument.viewBox.y)
    }

    mutating func build() -> Result {
        let root = Self.container(size)
        root.masksToBounds = true  // the viewBox clip
        root.allowsGroupOpacity = true
        for child in document.art.children { add(child, to: root, transform: base, style: Style(), inRail: false) }
        add(document.rail, to: root, transform: base, style: Style(), inRail: true)
        return Result(root: root, movers: movers, railFill: railFill)
    }

    private static func container(_ size: CGSize) -> CALayer {
        let layer = CALayer()
        layer.frame = CGRect(origin: .zero, size: size)
        layer.contentsScale = NSScreen.main?.backingScaleFactor ?? 2
        return layer
    }

    // MARK: Nodes

    private mutating func add(_ node: SceneNode, to parent: CALayer, transform: CGAffineTransform, style inherited: Style, inRail: Bool) {
        var style = inherited
        style.apply(node)
        var local = transform
        if let t = node["transform"] { local = Self.parseTransform(t).concatenating(local) }
        // Progress offsets (style="transform:translateX(…px)") stay on the layer, so they can slide.
        let offsetX = node["style"].flatMap(Self.translateX).map { CGFloat($0) * scale } ?? 0

        switch node.kind {
        case .group:
            let layer = Self.container(size)
            if let opacity = node["opacity"].flatMap(Double.init) { layer.opacity = Float(opacity) }
            if let clip = node["clip-path"], let mask = clipMask(clip, transform: local) { layer.mask = mask }
            if offsetX != 0 { layer.transform = CATransform3DMakeTranslation(offsetX, 0, 0) }
            parent.addSublayer(layer)
            for child in node.children { add(child, to: layer, transform: local, style: style, inRail: inRail) }
            if let motion = node.motionClass.flatMap(BannerArt.Motion.init(rawValue:)) {
                movers.append(Mover(motion: motion, layer: layer, pivot: pivot(for: motion, node: node, transform: local),
                                    offsetX: offsetX))
            }
        case .rect where inRail && node["fill"] == BannerArt.accent:
            // The rail's done fill: a rounded layer anchored at the left, so its width can slide
            // from any length to any other (including nothing).
            let box = Self.rect(node).applying(local)
            let fill = CALayer()
            fill.anchorPoint = CGPoint(x: 0, y: 0.5)
            fill.bounds = CGRect(x: 0, y: 0, width: max(0, box.width), height: box.height)
            fill.position = CGPoint(x: box.minX, y: box.midY)
            fill.cornerRadius = CGFloat(Double(node["rx"] ?? "0") ?? 0) * scale
            fill.backgroundColor = Self.color(BannerArt.accent)
            parent.addSublayer(fill)
            railFill = fill
        case .path, .rect, .circle, .ellipse:
            guard let path = Self.shape(node) else { return }
            var placed = local
            guard let points = path.copy(using: &placed) else { return }
            let layers = shapeLayers(node, path: points, style: style)
            for layer in layers {
                if let opacity = node["opacity"].flatMap(Double.init) { layer.opacity = Float(opacity) }
                if let clip = node["clip-path"], let mask = clipMask(clip, transform: transform) { layer.mask = mask }
                parent.addSublayer(layer)
            }
            if let motion = node.motionClass.flatMap(BannerArt.Motion.init(rawValue:)), let layer = layers.first {
                // Shapes with their own motion (the tea steam, the stars) animate on their layer.
                movers.append(Mover(motion: motion, layer: layer, pivot: CGPoint(x: points.boundingBoxOfPath.midX, y: points.boundingBoxOfPath.midY), offsetX: 0))
            }
        case .linearGradient, .stop, .pattern, .clipPath:
            break
        }
    }

    /// The fill and stroke of one shape: a CAShapeLayer, or a gradient or dot pattern masked to it.
    private func shapeLayers(_ node: SceneNode, path: CGPath, style: Style) -> [CALayer] {
        let frame = CGRect(origin: .zero, size: size)
        var out: [CALayer] = []
        let fillRef = style.fill.flatMap(Self.reference)
        // A zero-size rect draws nothing in SVG; the rail's empty fill still gets a layer so it can grow.
        let emptyRect = node.kind == .rect && (Self.rect(node).width <= 0 || Self.rect(node).height <= 0)

        if let id = fillRef, let def = document.definition(id), !emptyRect {
            if def.kind == .linearGradient {
                out.append(gradient(def, in: path, frame: frame))
            } else if def.kind == .pattern {
                out.append(pattern(def, in: path, frame: frame))
            }
        }
        let shape = CAShapeLayer()
        shape.frame = frame
        shape.contentsScale = NSScreen.main?.backingScaleFactor ?? 2
        shape.path = emptyRect ? CGPath(rect: .zero, transform: nil) : path
        if fillRef == nil, let fill = style.fill, let color = Self.color(fill, alpha: style.fillOpacity) {
            shape.fillColor = color
        } else {
            shape.fillColor = nil
        }
        if let stroke = style.stroke, let color = Self.color(stroke) {
            shape.strokeColor = color
            shape.lineWidth = style.strokeWidth * scale
            shape.lineCap = style.lineCap
            shape.lineJoin = style.lineJoin
            shape.miterLimit = 4  // SVG's default
            if let dash = style.dash, !dash.isEmpty {
                shape.lineDashPattern = dash.map { NSNumber(value: Double($0 * scale)) }
            }
        }
        if shape.fillColor != nil || shape.strokeColor != nil || emptyRect { out.append(shape) }
        return out
    }

    private func gradient(_ def: SceneNode, in path: CGPath, frame: CGRect) -> CALayer {
        let box = path.boundingBoxOfPath
        let layer = CAGradientLayer()
        layer.frame = box
        layer.contentsScale = NSScreen.main?.backingScaleFactor ?? 2
        let stops = def.children.filter { $0.kind == .stop }
        layer.colors = stops.compactMap { $0["stop-color"].flatMap { Self.color($0) } }
        layer.locations = stops.map { NSNumber(value: Double($0["offset"] ?? "0") ?? 0) }
        let x1 = Double(def["x1"] ?? "0") ?? 0, y1 = Double(def["y1"] ?? "0") ?? 0
        let x2 = Double(def["x2"] ?? "1") ?? 1, y2 = Double(def["y2"] ?? "0") ?? 0
        layer.startPoint = CGPoint(x: x1, y: y1)
        layer.endPoint = CGPoint(x: x2, y: y2)
        if !Self.isRect(path) {
            let mask = CAShapeLayer()
            var shift = CGAffineTransform(translationX: -box.minX, y: -box.minY)
            mask.path = path.copy(using: &shift)
            layer.mask = mask
        }
        return layer
    }

    /// The Make file's stippling: one dot per 5-unit tile, as a single path.
    private func pattern(_ def: SceneNode, in path: CGPath, frame: CGRect) -> CALayer {
        let tileW = Double(def["width"] ?? "5") ?? 5, tileH = Double(def["height"] ?? "5") ?? 5
        let layer = CAShapeLayer()
        layer.frame = frame
        layer.contentsScale = NSScreen.main?.backingScaleFactor ?? 2
        guard let dot = def.children.first(where: { $0.kind == .circle }) else { return layer }
        let cx = Double(dot["cx"] ?? "0") ?? 0, cy = Double(dot["cy"] ?? "0") ?? 0, r = Double(dot["r"] ?? "0") ?? 0
        let alpha = (Double(dot["opacity"] ?? "1") ?? 1)
        // Back from points to scene units to find which tiles the shape covers.
        let box = path.boundingBoxOfPath.applying(base.inverted())
        let dots = CGMutablePath()
        var ty = (box.minY / tileH).rounded(.down) * tileH
        while ty < box.maxY {
            var tx = (box.minX / tileW).rounded(.down) * tileW
            while tx < box.maxX {
                let center = CGPoint(x: tx + cx, y: ty + cy)
                if box.contains(center) {
                    dots.addEllipse(in: CGRect(x: center.x - r, y: center.y - r, width: 2 * r, height: 2 * r), transform: base)
                }
                tx += tileW
            }
            ty += tileH
        }
        layer.path = dots
        layer.fillColor = dot["fill"].flatMap { Self.color($0, alpha: alpha) }
        let mask = CAShapeLayer()
        mask.path = path
        layer.mask = mask
        return layer
    }

    private func clipMask(_ reference: String, transform: CGAffineTransform) -> CALayer? {
        guard let id = Self.reference(reference), let def = document.definition(id) else { return nil }
        let combined = CGMutablePath()
        for child in def.children {
            guard let path = Self.shape(child) else { continue }
            combined.addPath(path, transform: transform)
        }
        let mask = CAShapeLayer()
        mask.frame = CGRect(origin: .zero, size: size)
        mask.path = combined
        return mask
    }

    /// Where a moving group turns: the Make file's CSS origins (`transform-box: fill-box`).
    private func pivot(for motion: BannerArt.Motion, node: SceneNode, transform: CGAffineTransform) -> CGPoint {
        let box = bounds(of: node, transform: transform)
        switch motion {
        case .sway: return CGPoint(x: box.midX, y: box.maxY)     // bottom centre
        case .linen: return CGPoint(x: box.midX, y: box.minY)    // top centre
        default: return CGPoint(x: box.midX, y: box.midY)
        }
    }

    private func bounds(of node: SceneNode, transform: CGAffineTransform) -> CGRect {
        var local = transform
        if node.kind == .group, let t = node["transform"] { local = Self.parseTransform(t).concatenating(transform) }
        if node.kind == .group {
            return node.children.reduce(CGRect.null) { $0.union(bounds(of: $1, transform: local)) }
        }
        guard let path = Self.shape(node) else { return .null }
        var placed = local
        return path.copy(using: &placed)?.boundingBoxOfPath ?? .null
    }

    // MARK: Parsing

    static func shape(_ node: SceneNode) -> CGPath? {
        func n(_ key: String) -> CGFloat { CGFloat(Double(node[key] ?? "0") ?? 0) }
        switch node.kind {
        case .path:
            guard let d = node["d"], let elements = try? SVGPath.parse(d) else { return nil }
            return path(elements)
        case .rect:
            let rect = Self.rect(node)
            guard rect.width > 0, rect.height > 0 else { return CGPath(rect: rect, transform: nil) }
            var rx = node["rx"].flatMap(Double.init).map { CGFloat($0) }
            var ry = node["ry"].flatMap(Double.init).map { CGFloat($0) }
            if rx == nil { rx = ry }
            if ry == nil { ry = rx }
            let cx = min(rx ?? 0, rect.width / 2), cy = min(ry ?? 0, rect.height / 2)
            return cx > 0 && cy > 0 ? CGPath(roundedRect: rect, cornerWidth: cx, cornerHeight: cy, transform: nil)
                : CGPath(rect: rect, transform: nil)
        case .circle:
            let r = n("r")
            return CGPath(ellipseIn: CGRect(x: n("cx") - r, y: n("cy") - r, width: 2 * r, height: 2 * r), transform: nil)
        case .ellipse:
            let rx = n("rx"), ry = n("ry")
            return CGPath(ellipseIn: CGRect(x: n("cx") - rx, y: n("cy") - ry, width: 2 * rx, height: 2 * ry), transform: nil)
        default:
            return nil
        }
    }

    static func rect(_ node: SceneNode) -> CGRect {
        func n(_ key: String) -> CGFloat { CGFloat(Double(node[key] ?? "0") ?? 0) }
        return CGRect(x: n("x"), y: n("y"), width: n("width"), height: n("height"))
    }

    static func path(_ elements: [SVGPath.Element]) -> CGPath {
        let path = CGMutablePath()
        for element in elements {
            switch element {
            case .move(let p): path.move(to: CGPoint(x: p.x, y: p.y))
            case .line(let p): path.addLine(to: CGPoint(x: p.x, y: p.y))
            case .quad(let c, let p): path.addQuadCurve(to: CGPoint(x: p.x, y: p.y), control: CGPoint(x: c.x, y: c.y))
            case .cubic(let c1, let c2, let p):
                path.addCurve(to: CGPoint(x: p.x, y: p.y), control1: CGPoint(x: c1.x, y: c1.y), control2: CGPoint(x: c2.x, y: c2.y))
            case .close: path.closeSubpath()
            }
        }
        return path
    }

    private static func isRect(_ path: CGPath) -> Bool {
        var count = 0
        var curves = false
        path.applyWithBlock { element in
            count += 1
            if element.pointee.type == .addCurveToPoint || element.pointee.type == .addQuadCurveToPoint { curves = true }
        }
        return !curves && count <= 6 && path.boundingBoxOfPath.width > 0
    }

    /// `translate(219 8)` (the only transform the art uses).
    static func parseTransform(_ text: String) -> CGAffineTransform {
        let numbers = text.replacingOccurrences(of: "translate(", with: "").replacingOccurrences(of: ")", with: "")
            .split(whereSeparator: { $0 == " " || $0 == "," }).compactMap { Double($0) }
        guard text.hasPrefix("translate"), let x = numbers.first else { return .identity }
        return CGAffineTransform(translationX: x, y: numbers.count > 1 ? numbers[1] : 0)
    }

    /// `transform:translateX(67px)` → 67.
    static func translateX(_ style: String) -> Double? {
        guard let start = style.range(of: "translateX(")?.upperBound,
              let end = style[start...].range(of: "px)")?.lowerBound else { return nil }
        return Double(style[start..<end])
    }

    static func reference(_ value: String) -> String? {
        guard value.hasPrefix("url(#"), value.hasSuffix(")") else { return nil }
        return String(value.dropFirst(5).dropLast())
    }

    static func color(_ hex: String, alpha: CGFloat = 1) -> CGColor? {
        guard hex.hasPrefix("#") else { return nil }
        var digits = String(hex.dropFirst())
        if digits.count == 3 { digits = digits.map { "\($0)\($0)" }.joined() }
        guard digits.count == 6, let value = UInt32(digits, radix: 16) else { return nil }
        return CGColor(srgbRed: CGFloat((value >> 16) & 0xFF) / 255, green: CGFloat((value >> 8) & 0xFF) / 255,
                       blue: CGFloat(value & 0xFF) / 255, alpha: alpha)
    }
}
