#if DEBUG
import AppKit
import QuartzCore

/// Writes a view's Core Animation layer tree as SVG — how Coco's real artwork gets into
/// Figma as editable vectors (see docs/DESIGN_SYSTEM.md). Debug builds only.
///
/// Handles what CocoLayerView uses: shape layers (fill, stroke, caps, joins, even-odd,
/// strokeStart/End), plain layers with a background color and corner radius, affine
/// transforms and sublayer transforms, opacity and hidden layers. Groups are named after
/// the view's stored properties (“ears 1”, “eyes 2 open”…) so the layers read well in Figma.
enum LayerSVGExporter {
    static func svg(of view: NSView) -> String {
        guard let host = view.layer else { return "" }
        let names = propertyNames(of: view)
        let height = view.bounds.height
        var out = [String]()
        out.append(#"<svg xmlns="http://www.w3.org/2000/svg" width="\#(n(view.bounds.width))" height="\#(n(height))" viewBox="0 0 \#(n(view.bounds.width)) \#(n(height))">"#)
        for layer in host.sublayers ?? [] {
            emit(layer, host: host, height: height, opacity: 1, names: names, indent: 1, into: &out)
        }
        out.append("</svg>")
        return out.joined(separator: "\n")
    }

    // MARK: - Tree

    private static func emit(_ layer: CALayer, host: CALayer, height: CGFloat, opacity: Float,
                             names: [ObjectIdentifier: String], indent: Int, into out: inout [String]) {
        let alpha = opacity * layer.opacity
        guard !layer.isHidden, alpha > 0.001 else { return }
        let pad = String(repeating: "  ", count: indent)
        let name = names[ObjectIdentifier(layer)]
        let children = layer.sublayers ?? []
        let ownShape = shapeElement(layer, host: host, height: height, alpha: alpha)
        if let name, ownShape != nil || !children.isEmpty {
            out.append(#"\#(pad)<g id="\#(name)">"#)
        }
        if let ownShape { out.append(pad + "  " + ownShape) }
        for child in children {
            emit(child, host: host, height: height, opacity: alpha, names: names, indent: indent + 1, into: &out)
        }
        if name != nil, ownShape != nil || !children.isEmpty { out.append("\(pad)</g>") }
    }

    /// The layer's own drawing as one `<path>`, in the host's y-down coordinates.
    private static func shapeElement(_ layer: CALayer, host: CALayer, height: CGFloat, alpha: Float) -> String? {
        let toHost = transform(from: layer, to: host, height: height)
        let scale = sqrt(abs(toHost.a * toHost.d - toHost.b * toHost.c))
        if let shape = layer as? CAShapeLayer, var path = shape.path {
            if shape.strokeStart > 0 || shape.strokeEnd < 1 {
                path = trimmed(path, from: shape.strokeStart, to: shape.strokeEnd)
            }
            var transform = toHost
            guard let placed = path.copy(using: &transform) else { return nil }
            var attributes = [#"d="\#(pathData(placed))""#]
            if let fill = shape.fillColor, fill.alpha > 0 {
                attributes.append(paint("fill", fill))
                if shape.fillRule == .evenOdd { attributes.append(#"fill-rule="evenodd""#) }
            } else {
                attributes.append(#"fill="none""#)
            }
            if let stroke = shape.strokeColor, stroke.alpha > 0, shape.lineWidth > 0 {
                attributes.append(paint("stroke", stroke))
                attributes.append(#"stroke-width="\#(n(shape.lineWidth * scale))""#)
                let cap = shape.lineCap == .round ? "round" : shape.lineCap == .square ? "square" : "butt"
                let join = shape.lineJoin == .round ? "round" : shape.lineJoin == .bevel ? "bevel" : "miter"
                attributes.append(#"stroke-linecap="\#(cap)" stroke-linejoin="\#(join)""#)
            }
            if alpha < 0.999 { attributes.append(#"opacity="\#(n(CGFloat(alpha)))""#) }
            return "<path " + attributes.joined(separator: " ") + "/>"
        }
        if let background = layer.backgroundColor, background.alpha > 0 {
            let rect = CGPath(roundedRect: layer.bounds, cornerWidth: min(layer.cornerRadius, layer.bounds.width / 2),
                              cornerHeight: min(layer.cornerRadius, layer.bounds.height / 2), transform: nil)
            var transform = toHost
            guard let placed = rect.copy(using: &transform) else { return nil }
            var element = #"<path d="\#(pathData(placed))" \#(paint("fill", background))"#
            if alpha < 0.999 { element += #" opacity="\#(n(CGFloat(alpha)))""# }
            return element + "/>"
        }
        return nil
    }

    /// Layer space → host space (via Core Animation's own conversion), then flipped to y-down.
    private static func transform(from layer: CALayer, to host: CALayer, height: CGFloat) -> CGAffineTransform {
        let o = layer.convert(CGPoint.zero, to: host)
        let x = layer.convert(CGPoint(x: 1, y: 0), to: host)
        let y = layer.convert(CGPoint(x: 0, y: 1), to: host)
        let affine = CGAffineTransform(a: x.x - o.x, b: x.y - o.y, c: y.x - o.x, d: y.y - o.y, tx: o.x, ty: o.y)
        let flip = host.contentsAreFlipped() ? .identity : CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: height)
        return affine.concatenating(flip)
    }

    // MARK: - Paths

    nonisolated private static func pathData(_ path: CGPath) -> String {
        var d = ""
        path.applyWithBlock { element in
            let e = element.pointee
            func p(_ i: Int) -> String { "\(n(e.points[i].x)) \(n(e.points[i].y))" }
            switch e.type {
            case .moveToPoint: d += "M\(p(0))"
            case .addLineToPoint: d += "L\(p(0))"
            case .addQuadCurveToPoint: d += "Q\(p(0)) \(p(1))"
            case .addCurveToPoint: d += "C\(p(0)) \(p(1)) \(p(2))"
            case .closeSubpath: d += "Z"
            @unknown default: break
            }
        }
        return d
    }

    /// The part of a path between two fractions of its length (for strokeStart / strokeEnd).
    nonisolated private static func trimmed(_ path: CGPath, from start: CGFloat, to end: CGFloat) -> CGPath {
        var points = [[CGPoint]]()
        var current = CGPoint.zero, subpathStart = CGPoint.zero
        path.applyWithBlock { element in
            let e = element.pointee
            switch e.type {
            case .moveToPoint:
                current = e.points[0]; subpathStart = current; points.append([current])
            case .addLineToPoint:
                current = e.points[0]; points[points.count - 1].append(current)
            case .addQuadCurveToPoint:
                let (c, to) = (e.points[0], e.points[1])
                for i in 1...24 {
                    let t = CGFloat(i) / 24, u = 1 - t
                    points[points.count - 1].append(CGPoint(x: u * u * current.x + 2 * u * t * c.x + t * t * to.x,
                                                            y: u * u * current.y + 2 * u * t * c.y + t * t * to.y))
                }
                current = to
            case .addCurveToPoint:
                let (c1, c2, to) = (e.points[0], e.points[1], e.points[2])
                for i in 1...24 {
                    let t = CGFloat(i) / 24, u = 1 - t
                    let x = u * u * u * current.x + 3 * u * u * t * c1.x + 3 * u * t * t * c2.x + t * t * t * to.x
                    let y = u * u * u * current.y + 3 * u * u * t * c1.y + 3 * u * t * t * c2.y + t * t * t * to.y
                    points[points.count - 1].append(CGPoint(x: x, y: y))
                }
                current = to
            case .closeSubpath:
                current = subpathStart; points[points.count - 1].append(current)
            @unknown default: break
            }
        }
        let polyline = points.flatMap { $0 }
        let lengths = zip(polyline, polyline.dropFirst()).map { hypot($1.x - $0.x, $1.y - $0.y) }
        let total = lengths.reduce(0, +)
        let (from, to) = (start * total, end * total)
        let result = CGMutablePath()
        var walked: CGFloat = 0
        for (i, length) in lengths.enumerated() {
            let (a, b) = (polyline[i], polyline[i + 1])
            let segStart = max(from, walked), segEnd = min(to, walked + length)
            if segEnd > segStart, length > 0 {
                let p0 = CGPoint(x: a.x + (b.x - a.x) * (segStart - walked) / length, y: a.y + (b.y - a.y) * (segStart - walked) / length)
                let p1 = CGPoint(x: a.x + (b.x - a.x) * (segEnd - walked) / length, y: a.y + (b.y - a.y) * (segEnd - walked) / length)
                if result.isEmpty || result.currentPoint != p0 { result.move(to: p0) }
                result.addLine(to: p1)
            }
            walked += length
        }
        return result
    }

    // MARK: - Names and colors

    /// Maps each layer held in a stored property (including arrays, tuples and nested
    /// objects such as an eye) to a readable name.
    private static func propertyNames(of view: NSView) -> [ObjectIdentifier: String] {
        var names = [ObjectIdentifier: String]()
        func visit(_ value: Any, _ name: String, depth: Int) {
            guard depth < 4 else { return }
            if let layer = value as? CALayer {
                if names[ObjectIdentifier(layer)] == nil { names[ObjectIdentifier(layer)] = name }
                return
            }
            let mirror = Mirror(reflecting: value)
            switch mirror.displayStyle {
            case .collection?:
                for (index, child) in mirror.children.enumerated() { visit(child.value, "\(name) \(index + 1)", depth: depth + 1) }
            case .tuple?, .class?, .struct?:
                for child in mirror.children {
                    let label = (child.label ?? "").hasPrefix(".") ? String(child.label!.dropFirst()) : (child.label ?? "")
                    visit(child.value, label.isEmpty ? name : "\(name) \(label)", depth: depth + 1)
                }
            default:
                break
            }
        }
        for child in Mirror(reflecting: view).children {
            guard let label = child.label else { continue }
            visit(child.value, label, depth: 0)
        }
        return names
    }

    private static func paint(_ attribute: String, _ color: CGColor) -> String {
        let srgb = color.converted(to: CGColorSpace(name: CGColorSpace.sRGB)!, intent: .defaultIntent, options: nil) ?? color
        let c = srgb.components ?? [0, 0, 0, 1]
        let (r, g, b) = c.count >= 3 ? (c[0], c[1], c[2]) : (c[0], c[0], c[0])
        let hex = String(format: "#%02X%02X%02X", Int((r * 255).rounded()), Int((g * 255).rounded()), Int((b * 255).rounded()))
        var text = #"\#(attribute)="\#(hex)""#
        if srgb.alpha < 0.999 { text += #" \#(attribute)-opacity="\#(n(srgb.alpha))""# }
        return text
    }

    nonisolated private static func n(_ value: CGFloat) -> String {
        let text = String(format: "%.2f", value)
        return text.hasSuffix(".00") ? String(text.dropLast(3)) : text
    }
}
#endif
