import AppKit
import QuartzCore

/// Three "z"s drifting up from Pip's head while it naps.
/// Pure Core Animation: once started, the app does no work per frame.
final class SleepyZView: NSView {
    private let zLayers: [CATextLayer]

    /// Where the Zs start, in window coordinates (origin bottom-left), next to the
    /// top-right of the napping blob.
    static let start = CGPoint(x: 204, y: 60)
    static let rise = CGPoint(x: 16, y: 36)
    private var start: CGPoint { CGPoint(x: Self.start.x * scale, y: Self.start.y * scale) }
    private var rise: CGPoint { CGPoint(x: Self.rise.x * scale, y: Self.rise.y * scale) }
    private let cycle: CFTimeInterval = 2.9

    /// Matches the chosen Pip size.
    var scale: CGFloat = 1 {
        didSet { if isAnimating { stopAnimating(); startAnimating() } }
    }

    var isAnimating = false {
        didSet { if isAnimating != oldValue { isAnimating ? startAnimating() : stopAnimating() } }
    }

    override init(frame: NSRect) {
        let root = CALayer()
        zLayers = (0..<3).map { _ in CATextLayer() }
        super.init(frame: frame)
        layer = root          // layer-hosting view: we own the layer tree
        wantsLayer = true

        let base = NSFont.systemFont(ofSize: 15, weight: .heavy)
        let font = base.fontDescriptor.withDesign(.rounded).flatMap { NSFont(descriptor: $0, size: 15) } ?? base
        for z in zLayers {
            z.string = "z"
            z.font = font
            z.fontSize = 15
            z.foregroundColor = NSColor(red: 0.36, green: 0.36, blue: 0.82, alpha: 1).cgColor
            z.alignmentMode = .center
            z.contentsScale = NSScreen.main?.backingScaleFactor ?? 2
            z.bounds = CGRect(x: 0, y: 0, width: 20, height: 22)
            z.position = SleepyZView.start
            z.opacity = 0
            z.shadowColor = NSColor.white.cgColor
            z.shadowOpacity = 0.9
            z.shadowRadius = 1.5
            z.shadowOffset = .zero
            root.addSublayer(z)
        }
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    // Never intercept clicks.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        let scale = window?.backingScaleFactor ?? 2
        zLayers.forEach { $0.contentsScale = scale }
    }

    private func startAnimating() {
        let now = CACurrentMediaTime()
        for (i, z) in zLayers.enumerated() {
            let move = CAKeyframeAnimation(keyPath: "position")
            move.values = [
                start,
                CGPoint(x: start.x + rise.x * 0.45 + 2, y: start.y + rise.y * 0.5),
                CGPoint(x: start.x + rise.x, y: start.y + rise.y),
            ].map { NSValue(point: $0) }

            let fade = CAKeyframeAnimation(keyPath: "opacity")
            fade.values = [0, 1, 1, 0]
            fade.keyTimes = [0, 0.25, 0.6, 1]

            let grow = CABasicAnimation(keyPath: "transform.scale")
            grow.fromValue = 0.85 * scale
            grow.toValue = 1.5 * scale

            let group = CAAnimationGroup()
            group.animations = [move, fade, grow]
            group.duration = cycle
            group.repeatCount = .infinity
            // Stagger the three Zs evenly through the cycle.
            group.beginTime = now - cycle * Double(i) / 3
            z.add(group, forKey: "float")
        }
    }

    private func stopAnimating() {
        zLayers.forEach { $0.removeAnimation(forKey: "float") }
    }
}
