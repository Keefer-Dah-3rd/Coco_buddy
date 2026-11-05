import Foundation

/// SVG path data (`d`) turned into absolute drawing steps, so the app can build a CGPath that
/// follows the original line art exactly. Handles every command (M L H V C S Q T A Z, absolute
/// and relative, with implicit repeats) and the compact number forms the Make source uses
/// (`m0 41 5-34h13`, `.45`, arc flags written together as `0 0 1-13-17`). Arcs become cubic
/// Béziers, as browsers draw them.
public enum SVGPath {
    public struct Point: Sendable, Equatable {
        public var x: Double
        public var y: Double
        public init(_ x: Double, _ y: Double) { self.x = x; self.y = y }
    }

    public enum Element: Sendable, Equatable {
        case move(Point)
        case line(Point)
        case quad(Point, Point)
        case cubic(Point, Point, Point)
        case close
    }

    public struct ParseError: Error, CustomStringConvertible {
        public let description: String
    }

    public static func parse(_ d: String) throws -> [Element] {
        var scanner = Tokens(Array(d.utf8))
        var out: [Element] = []
        var current = Point(0, 0)
        var start = Point(0, 0)
        // The last control point, for S/T reflections.
        var lastCubic: Point?
        var lastQuad: Point?
        var command: UInt8 = 0

        while true {
            scanner.skipSeparators()
            guard !scanner.atEnd else { break }
            if let letter = scanner.commandLetter() {
                command = letter
            } else if command == 0 {
                throw ParseError(description: "Path data must start with a command: \(d)")
            } else if command == UInt8(ascii: "M") {
                command = UInt8(ascii: "L")  // numbers after a moveto are implicit linetos
            } else if command == UInt8(ascii: "m") {
                command = UInt8(ascii: "l")
            }
            let relative = command >= UInt8(ascii: "a")
            func abs(_ x: Double, _ y: Double) -> Point {
                relative ? Point(current.x + x, current.y + y) : Point(x, y)
            }
            var cubicControl: Point?
            var quadControl: Point?
            switch command | 0x20 {  // lowercase
            case UInt8(ascii: "m"):
                let p = abs(try scanner.number(), try scanner.number())
                out.append(.move(p)); current = p; start = p
            case UInt8(ascii: "l"):
                let p = abs(try scanner.number(), try scanner.number())
                out.append(.line(p)); current = p
            case UInt8(ascii: "h"):
                let x = try scanner.number()
                let p = Point(relative ? current.x + x : x, current.y)
                out.append(.line(p)); current = p
            case UInt8(ascii: "v"):
                let y = try scanner.number()
                let p = Point(current.x, relative ? current.y + y : y)
                out.append(.line(p)); current = p
            case UInt8(ascii: "c"):
                let c1 = abs(try scanner.number(), try scanner.number())
                let c2 = abs(try scanner.number(), try scanner.number())
                let p = abs(try scanner.number(), try scanner.number())
                out.append(.cubic(c1, c2, p)); current = p; cubicControl = c2
            case UInt8(ascii: "s"):
                let c1 = lastCubic.map { Point(2 * current.x - $0.x, 2 * current.y - $0.y) } ?? current
                let c2 = abs(try scanner.number(), try scanner.number())
                let p = abs(try scanner.number(), try scanner.number())
                out.append(.cubic(c1, c2, p)); current = p; cubicControl = c2
            case UInt8(ascii: "q"):
                let c = abs(try scanner.number(), try scanner.number())
                let p = abs(try scanner.number(), try scanner.number())
                out.append(.quad(c, p)); current = p; quadControl = c
            case UInt8(ascii: "t"):
                let c = lastQuad.map { Point(2 * current.x - $0.x, 2 * current.y - $0.y) } ?? current
                let p = abs(try scanner.number(), try scanner.number())
                out.append(.quad(c, p)); current = p; quadControl = c
            case UInt8(ascii: "a"):
                let rx = try scanner.number(), ry = try scanner.number()
                let rotation = try scanner.number()
                let large = try scanner.flag(), sweep = try scanner.flag()
                let p = abs(try scanner.number(), try scanner.number())
                out += arc(from: current, to: p, rx: rx, ry: ry, rotation: rotation, large: large, sweep: sweep)
                current = p
            case UInt8(ascii: "z"):
                out.append(.close); current = start
            default:
                throw ParseError(description: "Unknown path command \(Character(UnicodeScalar(command))) in \(d)")
            }
            lastCubic = cubicControl
            lastQuad = quadControl
            if command | 0x20 == UInt8(ascii: "z") { command = 0 }
        }
        return out
    }

    // MARK: Arcs (SVG 1.1 appendix F.6)

    static func arc(from p0: Point, to p1: Point, rx: Double, ry: Double, rotation: Double,
                    large: Bool, sweep: Bool) -> [Element] {
        if p0 == p1 { return [] }
        var rx = Swift.abs(rx), ry = Swift.abs(ry)
        if rx == 0 || ry == 0 { return [.line(p1)] }
        let phi = rotation * .pi / 180
        let cosPhi = cos(phi), sinPhi = sin(phi)
        let dx = (p0.x - p1.x) / 2, dy = (p0.y - p1.y) / 2
        let x1 = cosPhi * dx + sinPhi * dy
        let y1 = -sinPhi * dx + cosPhi * dy
        let lambda = (x1 * x1) / (rx * rx) + (y1 * y1) / (ry * ry)
        if lambda > 1 { rx *= lambda.squareRoot(); ry *= lambda.squareRoot() }
        let num = rx * rx * ry * ry - rx * rx * y1 * y1 - ry * ry * x1 * x1
        let den = rx * rx * y1 * y1 + ry * ry * x1 * x1
        var coefficient = (max(0, num) / den).squareRoot()
        if large == sweep { coefficient = -coefficient }
        let cx1 = coefficient * rx * y1 / ry
        let cy1 = -coefficient * ry * x1 / rx
        let cx = cosPhi * cx1 - sinPhi * cy1 + (p0.x + p1.x) / 2
        let cy = sinPhi * cx1 + cosPhi * cy1 + (p0.y + p1.y) / 2

        func angle(_ ux: Double, _ uy: Double, _ vx: Double, _ vy: Double) -> Double {
            let a = atan2(ux * vy - uy * vx, ux * vx + uy * vy)
            return a
        }
        let theta1 = angle(1, 0, (x1 - cx1) / rx, (y1 - cy1) / ry)
        var delta = angle((x1 - cx1) / rx, (y1 - cy1) / ry, (-x1 - cx1) / rx, (-y1 - cy1) / ry)
        if !sweep, delta > 0 { delta -= 2 * .pi }
        if sweep, delta < 0 { delta += 2 * .pi }

        // Split into pieces of at most 90°, each a cubic.
        let segments = max(1, Int((Swift.abs(delta) / (.pi / 2)).rounded(.up)))
        let step = delta / Double(segments)
        let k = 4.0 / 3.0 * tan(step / 4)
        var out: [Element] = []
        var t = theta1
        func point(_ angle: Double) -> Point {
            let x = rx * cos(angle), y = ry * sin(angle)
            return Point(cosPhi * x - sinPhi * y + cx, sinPhi * x + cosPhi * y + cy)
        }
        func derivative(_ angle: Double) -> Point {
            let x = -rx * sin(angle), y = ry * cos(angle)
            return Point(cosPhi * x - sinPhi * y, sinPhi * x + cosPhi * y)
        }
        for index in 0..<segments {
            let t2 = t + step
            let a = point(t), b = index == segments - 1 ? p1 : point(t2)
            let da = derivative(t), db = derivative(t2)
            out.append(.cubic(Point(a.x + k * da.x, a.y + k * da.y), Point(b.x - k * db.x, b.y - k * db.y), b))
            t = t2
        }
        return out
    }

    // MARK: Tokens

    private struct Tokens {
        let bytes: [UInt8]
        var index = 0
        init(_ bytes: [UInt8]) { self.bytes = bytes }

        var atEnd: Bool { index >= bytes.count }

        mutating func skipSeparators() {
            while index < bytes.count, bytes[index] == 0x20 || bytes[index] == 0x2C || bytes[index] == 0x0A
                    || bytes[index] == 0x09 || bytes[index] == 0x0D { index += 1 }
        }

        mutating func commandLetter() -> UInt8? {
            guard index < bytes.count else { return nil }
            let c = bytes[index]
            // Letters other than e/E (exponents never start a token).
            guard (c >= 0x41 && c <= 0x5A) || (c >= 0x61 && c <= 0x7A), c != 0x65, c != 0x45 else { return nil }
            index += 1
            return c
        }

        mutating func flag() throws -> Bool {
            skipSeparators()
            guard index < bytes.count, bytes[index] == 0x30 || bytes[index] == 0x31 else {
                throw ParseError(description: "Expected an arc flag")
            }
            defer { index += 1 }
            return bytes[index] == 0x31
        }

        mutating func number() throws -> Double {
            skipSeparators()
            let begin = index
            if index < bytes.count, bytes[index] == 0x2D || bytes[index] == 0x2B { index += 1 }
            var sawDot = false, sawDigit = false
            while index < bytes.count {
                let c = bytes[index]
                if c >= 0x30 && c <= 0x39 { sawDigit = true; index += 1 }
                else if c == 0x2E, !sawDot { sawDot = true; index += 1 }
                else { break }
            }
            if sawDigit, index < bytes.count, bytes[index] == 0x65 || bytes[index] == 0x45 {
                var look = index + 1
                if look < bytes.count, bytes[look] == 0x2D || bytes[look] == 0x2B { look += 1 }
                if look < bytes.count, bytes[look] >= 0x30, bytes[look] <= 0x39 {
                    index = look
                    while index < bytes.count, bytes[index] >= 0x30, bytes[index] <= 0x39 { index += 1 }
                }
            }
            guard sawDigit, let value = Double(String(decoding: bytes[begin..<index], as: UTF8.self)) else {
                throw ParseError(description: "Expected a number at \(begin)")
            }
            return value
        }
    }
}
