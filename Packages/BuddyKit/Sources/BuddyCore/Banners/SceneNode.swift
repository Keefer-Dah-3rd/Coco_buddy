import Foundation

/// One element of an illustrated banner, in SVG terms: a group or a shape, with the same
/// presentation attributes the Figma Make source sets (`fill`, `stroke`, `transform`,
/// `clip-path`, `class`…). The banner art (`BannerArt`) builds these exactly as the Make
/// file's `IllustratedScene.tsx` builds its JSX, so the port can be checked attribute by
/// attribute against SVG exported from the original (see `BannerArtPortTests`). The app turns
/// the tree into Core Animation layers; `svg` turns it back into SVG for checks and Figma.
public struct SceneNode: Sendable, Equatable {
    public enum Kind: String, Sendable {
        case group = "g"
        case path, rect, circle, ellipse
        case linearGradient, stop, pattern, clipPath
    }

    public var kind: Kind
    /// SVG attribute names (kebab-case, as React writes them) to values.
    public var attributes: [String: String]
    public var children: [SceneNode]

    public init(_ kind: Kind, _ attributes: [String: String] = [:], children: [SceneNode] = []) {
        self.kind = kind
        self.attributes = attributes
        self.children = children
    }

    public subscript(_ name: String) -> String? { attributes[name] }

    /// The ambient-motion role from the Make file's CSS class (`vector-cloud`, `ferry-bob`…),
    /// if any. An empty class (React's `className=""`) counts as none.
    public var motionClass: String? {
        guard let value = attributes["class"], !value.isEmpty else { return nil }
        return value
    }
}

/// A whole banner frame: the gradient/pattern/clip definitions and the drawing. The text
/// (count, Coco's note, the time and weather) is not part of the art — SwiftUI draws it.
public struct SceneDocument: Sendable, Equatable {
    /// SVG viewBox: x, y, width, height. Every banner is 320 × 152, starting 44 above the
    /// ground line so the sky has room for the text.
    public static let viewBox = (x: 0.0, y: -44.0, width: 320.0, height: 152.0)

    public var defs: [SceneNode]
    public var art: SceneNode
    /// The progress rail and its thumb, drawn over the art (and over the text area).
    public var rail: SceneNode

    public init(defs: [SceneNode], art: SceneNode, rail: SceneNode) {
        self.defs = defs
        self.art = art
        self.rail = rail
    }

    /// A definition by id (`sky`, `dots`, `clip`, `carriage-window`…).
    public func definition(_ id: String) -> SceneNode? {
        defs.first { $0["id"] == id }
    }
}

// MARK: - Building

/// Lets the banner art read like the JSX it was ported from: `if`, `for … in`, optionals.
@resultBuilder
enum SceneBuilder {
    static func buildBlock(_ parts: [SceneNode]...) -> [SceneNode] { parts.flatMap { $0 } }
    static func buildExpression(_ node: SceneNode) -> [SceneNode] { [node] }
    static func buildExpression(_ nodes: [SceneNode]) -> [SceneNode] { nodes }
    static func buildOptional(_ part: [SceneNode]?) -> [SceneNode] { part ?? [] }
    static func buildEither(first: [SceneNode]) -> [SceneNode] { first }
    static func buildEither(second: [SceneNode]) -> [SceneNode] { second }
    static func buildArray(_ parts: [[SceneNode]]) -> [SceneNode] { parts.flatMap { $0 } }
}

/// Attribute lists for the DSL. Nil values are left out, as React leaves out `undefined`.
/// The DSL is internal to BuddyCore so its names never meet SwiftUI's `Path` or `Circle`.
typealias SceneAttributes = KeyValuePairs<String, String?>

private func attributes(_ pairs: SceneAttributes) -> [String: String] {
    var result: [String: String] = [:]
    for (key, value) in pairs { if let value { result[key] = value } }
    return result
}

func G(_ attrs: SceneAttributes = [:], @SceneBuilder _ content: () -> [SceneNode]) -> SceneNode {
    SceneNode(.group, attributes(attrs), children: content())
}

func Path(_ d: String, _ attrs: SceneAttributes = [:]) -> SceneNode {
    var all = attributes(attrs)
    all["d"] = d
    return SceneNode(.path, all)
}

func Rect(_ attrs: SceneAttributes) -> SceneNode { SceneNode(.rect, attributes(attrs)) }
func Circle(_ attrs: SceneAttributes) -> SceneNode { SceneNode(.circle, attributes(attrs)) }
func Ellipse(_ attrs: SceneAttributes) -> SceneNode { SceneNode(.ellipse, attributes(attrs)) }

/// A number the way JavaScript prints it in a template string: `67`, `8.321428571428571`, `-3`.
public func svgNumber(_ value: Double) -> String {
    if value == value.rounded(), abs(value) < 1e15 { return String(Int(value)) }
    return "\(value)"
}

// MARK: - Back to SVG

extension SceneNode {
    /// This node as SVG markup.
    public var svg: String {
        let attrs = attributes.sorted { $0.key < $1.key }
            .map { " \($0.key)=\"\(Self.escape($0.value))\"" }.joined()
        guard !children.isEmpty else { return "<\(kind.rawValue)\(attrs)/>" }
        return "<\(kind.rawValue)\(attrs)>" + children.map(\.svg).joined() + "</\(kind.rawValue)>"
    }

    static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "<", with: "&lt;")
    }
}

extension SceneDocument {
    /// A standalone SVG of the art and rail (no text), for checks, previews and Figma.
    public var svg: String {
        let box = Self.viewBox
        return "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"\(svgNumber(box.x)) \(svgNumber(box.y)) \(svgNumber(box.width)) \(svgNumber(box.height))\">"
            + "<defs>" + defs.map(\.svg).joined() + "</defs>"
            + "<g clip-path=\"url(#clip)\">" + art.svg + rail.svg + "</g></svg>"
    }
}

// MARK: - For Figma

extension SceneDocument {
    /// SVG shaped for Figma's importer, which the Coco-2 library's banner components are made
    /// from: the art at `width` points (166.25 tall at 350), the progress offsets as real
    /// `transform`s instead of CSS, the dot stippling as a single path (Figma drops `<pattern>`
    /// fills), and the layers that move named after their motion class (`vector-cloud`,
    /// `ferry-bob`…) so motion can be found and attached in Figma. Nothing else changes.
    public func figmaSVG(width: Double = 350, name: String) -> String {
        let box = Self.viewBox
        let height = box.height * width / box.width
        var used: [String: Int] = [:]
        func convert(_ node: SceneNode) -> SceneNode {
            var node = node
            node.children = node.children.map(convert)
            if let style = node.attributes.removeValue(forKey: "style"),
               let start = style.range(of: "translateX(")?.upperBound,
               let end = style[start...].range(of: "px)")?.lowerBound {
                let x = String(style[start..<end])
                node.attributes["transform"] = [node.attributes["transform"], "translate(\(x) 0)"].compactMap { $0 }.joined(separator: " ")
            }
            if let motion = node.attributes.removeValue(forKey: "class"), !motion.isEmpty {
                let count = used[motion, default: 0] + 1
                used[motion] = count
                node.attributes["id"] = count == 1 ? motion : "\(motion)-\(count)"
            }
            if node.kind == .rect, node["fill"] == "url(#\(BannerArt.Def.dots))", let pattern = definition(BannerArt.Def.dots) {
                node = Self.dots(pattern, in: node)
            }
            return node
        }
        let art = convert(self.art)
        let rail = convert(self.rail)
        let defs = self.defs.filter { $0.kind != .pattern }
        return "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"\(svgNumber(width))\" height=\"\(svgNumber(height))\" "
            + "viewBox=\"\(svgNumber(box.x)) \(svgNumber(box.y)) \(svgNumber(box.width)) \(svgNumber(box.height))\">"
            + "<defs>" + defs.map(\.svg).joined() + "</defs>"
            + "<g id=\"\(SceneNode.escape(name))\" clip-path=\"url(#clip)\">" + art.svg + rail.svg + "</g></svg>"
    }

    /// The stippling pattern written out as one path of dots over `rect`.
    private static func dots(_ pattern: SceneNode, in rect: SceneNode) -> SceneNode {
        func n(_ node: SceneNode, _ key: String, _ fallback: Double = 0) -> Double { Double(node[key] ?? "") ?? fallback }
        guard let dot = pattern.children.first(where: { $0.kind == .circle }) else { return rect }
        let tileW = n(pattern, "width", 5), tileH = n(pattern, "height", 5)
        let cx = n(dot, "cx"), cy = n(dot, "cy"), r = n(dot, "r")
        let x0 = n(rect, "x"), y0 = n(rect, "y"), w = n(rect, "width"), h = n(rect, "height")
        var d = ""
        var y = (y0 / tileH).rounded(.down) * tileH
        while y < y0 + h {
            var x = (x0 / tileW).rounded(.down) * tileW
            while x < x0 + w {
                let px = x + cx, py = y + cy
                if px >= x0, px <= x0 + w, py >= y0, py <= y0 + h {
                    d += "M\(svgNumber(px - r)) \(svgNumber(py))a\(svgNumber(r)) \(svgNumber(r)) 0 1 0 \(svgNumber(2 * r)) 0a\(svgNumber(r)) \(svgNumber(r)) 0 1 0 \(svgNumber(-2 * r)) 0Z"
                }
                x += tileW
            }
            y += tileH
        }
        return SceneNode(.path, ["id": "stippling", "d": d, "fill": dot["fill"] ?? BannerArt.ink,
                                 "fill-opacity": dot["opacity"] ?? "1", "stroke": "none"])
    }
}
