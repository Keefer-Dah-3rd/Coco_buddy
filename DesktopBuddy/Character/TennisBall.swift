import AppKit
import QuartzCore
import BuddyCharacter

/// The tennis ball: optic-yellow felt, white curved seams, and a soft highlight and
/// shadow so it reads as round. Shared by the ball in the world and the one in Coco's mouth.
enum TennisBall {
    static let felt = NSColor(hex: 0xD7E83C)
    static let edge = NSColor(hex: 0x8A9A1E)
    static let shade = NSColor(hex: 0x9FB223)
    static let seam = NSColor(hex: 0xF7F8EC)

    /// The two seams in a unit circle (y down): curves bowing toward each other, the classic
    /// tennis-ball pattern. Turning this is what makes the ball look like it spins.
    static let seams: CGPath = {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: -0.62, y: -0.78))
        path.addCurve(to: CGPoint(x: -0.62, y: 0.78), control1: CGPoint(x: -0.05, y: -0.42), control2: CGPoint(x: -0.05, y: 0.42))
        path.move(to: CGPoint(x: 0.62, y: -0.78))
        path.addCurve(to: CGPoint(x: 0.62, y: 0.78), control1: CGPoint(x: 0.05, y: -0.42), control2: CGPoint(x: 0.05, y: 0.42))
        return path
    }()
}

/// A drawn tennis ball for the desktop: felt, seams that turn with its spin, a fixed
/// highlight and lower shading (the light doesn't spin, so it looks like a sphere turning),
/// and a contact shadow on the floor that shrinks as the ball rises.
final class TennisBallLayer {
    let layer = CALayer()
    private let shadowSpot = CAShapeLayer()
    private let ball = CALayer()
    private let felt = CAShapeLayer()
    private let seams = CAShapeLayer()
    private let shading = CAGradientLayer()
    private let highlight = CAShapeLayer()
    private(set) var radius: CGFloat = 7

    init() {
        shadowSpot.fillColor = NSColor.black.cgColor
        layer.addSublayer(shadowSpot)
        layer.addSublayer(ball)
        felt.fillColor = TennisBall.felt.cgColor
        felt.strokeColor = TennisBall.edge.cgColor
        felt.lineWidth = 0.8
        ball.addSublayer(felt)
        seams.fillColor = nil
        seams.strokeColor = TennisBall.seam.cgColor
        seams.lineCap = .round
        ball.addSublayer(seams)
        shading.type = .radial
        shading.colors = [NSColor.white.withAlphaComponent(0).cgColor, TennisBall.shade.withAlphaComponent(0.55).cgColor]
        shading.startPoint = CGPoint(x: 0.38, y: 0.62)
        shading.endPoint = CGPoint(x: 1.05, y: -0.05)
        ball.addSublayer(shading)
        highlight.fillColor = NSColor.white.withAlphaComponent(0.55).cgColor
        ball.addSublayer(highlight)
        setRadius(7)
    }

    func setRadius(_ r: CGFloat) {
        radius = r
        let box = CGRect(x: -r, y: -r, width: 2 * r, height: 2 * r)
        ball.bounds = box
        ball.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        felt.path = CGPath(ellipseIn: box, transform: nil)
        var scale = CGAffineTransform(scaleX: r * 0.98, y: -r * 0.98)
        seams.path = TennisBall.seams.copy(using: &scale)
        seams.lineWidth = max(0.9, r * 0.16)
        seams.frame = box
        seams.bounds = box
        shading.frame = box
        let mask = CAShapeLayer()
        mask.path = CGPath(ellipseIn: CGRect(origin: .zero, size: box.size), transform: nil)
        shading.mask = mask
        highlight.path = CGPath(ellipseIn: CGRect(x: -r * 0.55, y: r * 0.18, width: r * 0.5, height: r * 0.34), transform: nil)
        shadowSpot.path = CGPath(ellipseIn: CGRect(x: -r * 1.1, y: -r * 0.35, width: r * 2.2, height: r * 0.7), transform: nil)
    }

    /// Places the ball: its floor contact point (in this layer's coordinates, y up), height
    /// above the floor and spin.
    func place(ground: CGPoint, height: CGFloat, spin: CGFloat) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        shadowSpot.position = ground
        let air = min(1, height / 120)
        shadowSpot.opacity = Float(0.28 * (1 - air * 0.7))
        shadowSpot.setAffineTransform(CGAffineTransform(scaleX: 1 - air * 0.45, y: 1 - air * 0.45))
        ball.position = CGPoint(x: ground.x, y: ground.y + radius + height)
        // Clockwise on screen for a positive spin (y is up here).
        seams.setAffineTransform(CGAffineTransform(rotationAngle: -spin))
        CATransaction.commit()
    }
}
