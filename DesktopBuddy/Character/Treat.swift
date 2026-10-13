import AppKit
import QuartzCore

/// A dog treat: a little bone-shaped biscuit, warm baked brown with a highlight and a few
/// baked-in dots — easy to tell from the yellow tennis ball, and clear on light or dark
/// desktops.
enum Treat {
    static let biscuit = NSColor(hex: 0xC9813F)
    static let edge = NSColor(hex: 0x7D4A22)
    static let highlight = NSColor(hex: 0xEBB57A)

    /// The bone in a box `length` long (y up), centred on the origin.
    static func bone(length: CGFloat) -> CGPath {
        let half = length / 2
        let knob = length * 0.2
        let bar = CGPath(roundedRect: CGRect(x: -half + knob, y: -knob * 0.62, width: length - 2 * knob, height: knob * 1.24),
                         cornerWidth: knob * 0.4, cornerHeight: knob * 0.4, transform: nil)
        var shape = bar
        for x in [-half + knob, half - knob] {
            for y in [-knob * 0.72, knob * 0.72] {
                shape = shape.union(CGPath(ellipseIn: CGRect(x: x - knob, y: y - knob, width: 2 * knob, height: 2 * knob), transform: nil))
            }
        }
        return shape
    }
}

/// Anything Coco chases, drawn on the desktop: its contact shadow on the floor and the thing
/// itself at a height above it, turning as it flies.
protocol TossedThing: AnyObject {
    var layer: CALayer { get }
    /// Size at Coco's full scale is 1.
    func setScale(_ scale: CGFloat)
    func place(ground: CGPoint, height: CGFloat, spin: CGFloat)
}

extension TennisBallLayer: TossedThing {
    func setScale(_ scale: CGFloat) {
        let r = 7 * scale
        if abs(radius - r) > 0.01 { setRadius(r) }
    }
}

/// The treat on the desktop: tumbles end over end through the air, then lies where it lands.
final class TreatLayer: TossedThing {
    let layer = CALayer()
    private let shadowSpot = CAShapeLayer()
    private let treat = CALayer()
    private let biscuit = CAShapeLayer()
    private let shine = CAShapeLayer()
    private let dots = CAShapeLayer()
    private var length: CGFloat = 0
    private var scale: CGFloat = 0

    init() {
        shadowSpot.fillColor = NSColor.black.cgColor
        layer.addSublayer(shadowSpot)
        layer.addSublayer(treat)
        biscuit.fillColor = Treat.biscuit.cgColor
        biscuit.strokeColor = Treat.edge.cgColor
        biscuit.lineWidth = 0.9
        treat.addSublayer(biscuit)
        shine.fillColor = nil
        shine.strokeColor = Treat.highlight.cgColor
        shine.lineCap = .round
        treat.addSublayer(shine)
        dots.fillColor = Treat.edge.withAlphaComponent(0.6).cgColor
        treat.addSublayer(dots)
        setScale(1)
    }

    func setScale(_ scale: CGFloat) {
        guard abs(self.scale - scale) > 0.01 else { return }
        self.scale = scale
        length = 18 * scale
        biscuit.path = Treat.bone(length: length)
        let highlight = CGMutablePath()
        highlight.move(to: CGPoint(x: -length * 0.24, y: length * 0.07))
        highlight.addLine(to: CGPoint(x: length * 0.2, y: length * 0.07))
        shine.path = highlight
        shine.lineWidth = max(0.8, length * 0.06)
        let marks = CGMutablePath()
        for x in [-0.12, 0.02, 0.15] {
            marks.addEllipse(in: CGRect(x: length * x - 0.5, y: -length * 0.06 - 0.5, width: 1, height: 1))
        }
        dots.path = marks
        shadowSpot.path = CGPath(ellipseIn: CGRect(x: -length * 0.5, y: -length * 0.11, width: length, height: length * 0.22), transform: nil)
    }

    func place(ground: CGPoint, height: CGFloat, spin: CGFloat) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        shadowSpot.position = ground
        let air = min(1, height / 100)
        shadowSpot.opacity = Float(0.26 * (1 - air * 0.7))
        shadowSpot.setAffineTransform(CGAffineTransform(scaleX: 1 - air * 0.45, y: 1 - air * 0.45))
        treat.position = CGPoint(x: ground.x, y: ground.y + length * 0.22 + height)
        treat.setAffineTransform(CGAffineTransform(rotationAngle: -spin))
        CATransaction.commit()
    }
}
