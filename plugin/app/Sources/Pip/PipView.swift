import AppKit
import SwiftUI

// MARK: - Palette

enum PipColors {
    static let face = Color(red: 0.16, green: 0.12, blue: 0.20)
    static let cheek = Color(red: 1.00, green: 0.45, blue: 0.60)
    static let accent = Color(red: 0.42, green: 0.40, blue: 0.90)
    /// Glass tint: a cool top fading to a warm bottom.
    static let tintTop = Color(red: 0.78, green: 0.86, blue: 1.00)
    static let tintBottom = Color(red: 0.86, green: 0.76, blue: 1.00)
    static let sleepZ = Color(red: 0.36, green: 0.36, blue: 0.82)
    static let confetti: [Color] = [
        Color(red: 1.00, green: 0.78, blue: 0.20),
        Color(red: 0.35, green: 0.78, blue: 0.98),
        Color(red: 0.55, green: 0.88, blue: 0.45),
        Color(red: 0.98, green: 0.45, blue: 0.62),
        Color(red: 0.70, green: 0.55, blue: 1.00),
    ]
}

/// Snapshot rendering can't capture the system glass material, so it turns it off.
enum PipRender {
    @MainActor static var useSystemGlass = ProcessInfo.processInfo.environment["PIP_NO_GLASS"] == nil
    /// Snapshots freeze blinking so eyes are always open.
    @MainActor static var allowBlink = true
}

// MARK: - Root view (fills the floating window)

struct PipView: View {
    @ObservedObject var model: PipModel
    /// Eye glances and blinks are short one-off animations, so they stay cheap while calm.
    @State private var lookX: CGFloat = 0
    @State private var blink = false

    static let windowSize = CGSize(width: 300, height: 300)

    private var showsBubble: Bool { model.mood == .needsInput || model.mood == .done }

    /// How far Pip sinks below the screen edge: half its body while napping.
    private var sink: CGFloat {
        switch model.mood {
        case .sleeping: return 42
        case .hidden: return 180
        default: return 0
        }
    }

    var body: some View {
        // When calm (napping, working, or waiting a while), SwiftUI stops redrawing every frame.
        // Breathing then runs in Core Animation (AppDelegate.updateBreathing), which costs
        // almost no CPU. Only short events (waking, waving, celebrating) animate per frame.
        let calm = model.isCalm
        TimelineView(.animation(minimumInterval: 1.0 / 60, paused: calm)) { timeline in
            let t = calm ? 0 : timeline.date.timeIntervalSinceReferenceDate
            let since = calm ? 10 : max(0, timeline.date.timeIntervalSince(model.moodStarted))
            let pose = Pose(mood: model.mood, t: t, since: since, justWoke: model.justWoke)

            ZStack(alignment: .bottom) {
                if model.mood == .done {
                    ConfettiView(started: model.moodStarted, now: timeline.date)
                }
                if model.mood == .sleeping && !PipRender.useSystemGlass {
                    SnapshotZs()
                }

                // Ground shadow stays put and shrinks as Pip jumps.
                Ellipse()
                    .fill(Color.black.opacity(0.14))
                    .frame(width: 88 * pose.shadow, height: 10)
                    .blur(radius: 3)
                    .padding(.bottom, 4)
                    .opacity(model.mood == .hidden || model.mood == .sleeping ? 0 : 1)

                // The bubble rides along with Pip so it always sits just above its head.
                VStack(spacing: 8) {
                    if showsBubble {
                        SpeechBubble(source: model.source, message: model.message)
                            .transition(.scale(scale: 0.6, anchor: .bottom).combined(with: .opacity))
                            .id(model.moodStarted)
                    }
                    BlobView(mood: model.mood, t: t, pose: pose, calm: calm, lookX: lookX, blink: blink)
                        .frame(width: 128, height: 112)
                }
                .padding(.bottom, 8)
                .offset(y: pose.lift + sink)
            }
            .frame(width: Self.windowSize.width, height: Self.windowSize.height, alignment: .bottom)
        }
        .clipped()
        .contentShape(Rectangle())
        .onTapGesture { model.dismiss() }
        .animation(.spring(response: 0.5, dampingFraction: 0.62), value: model.mood)
        .animation(.spring(response: 0.5, dampingFraction: 0.62), value: model.moodStarted)
        .task(id: model.mood) { await glanceAround() }
    }

    /// Every few seconds: maybe look somewhere else, maybe blink.
    private func glanceAround() async {
        lookX = 0
        blink = false
        let mood = model.mood
        guard mood == .working || mood == .needsInput else { return }
        while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: UInt64(Double.random(in: 1.6...3.2) * 1_000_000_000))
            guard !Task.isCancelled else { return }
            if mood == .working {
                withAnimation(.easeInOut(duration: 0.45)) { lookX = [-7, -3, 0, 4, 7].randomElement()! }
            }
            if Bool.random() {
                withAnimation(.easeOut(duration: 0.07)) { blink = true }
                try? await Task.sleep(nanoseconds: 130_000_000)
                withAnimation(.easeIn(duration: 0.1)) { blink = false }
            }
        }
    }
}

// MARK: - Speech bubble

struct SpeechBubble: View {
    let source: String
    let message: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            if !source.isEmpty {
                Text(source.uppercased())
                    .font(.system(size: 9.5, weight: .bold, design: .rounded))
                    .tracking(0.6)
                    .foregroundColor(PipColors.accent)
            }
            Text(message)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundColor(Color(white: 0.12))
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 9)
        .frame(maxWidth: 250, alignment: .leading)
        .background(
            ZStack(alignment: .bottom) {
                RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.white)
                Rectangle().fill(Color.white)
                    .frame(width: 12, height: 12)
                    .rotationEffect(.degrees(45))
                    .offset(y: 5)
            }
            .compositingGroup()
            .shadow(color: .black.opacity(0.2), radius: 8, y: 3)
        )
        .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - Body transform

struct Pose {
    var sx = 1.0, sy = 1.0, tilt = 0.0, lift = 0.0, shadow = 1.0
    /// How much the liquid edge ripples.
    var wobble = 1.0
    /// How fast the liquid edge ripples.
    var flow = 1.0

    init(mood: Mood, t: Double, since: Double, justWoke: Bool) {
        let breathe = sin(t * 2.2)
        sx = 1 + 0.03 * breathe
        sy = 1 - 0.03 * breathe

        switch mood {
        case .sleeping, .hidden:
            // Slow, deep breaths; a little flattened like it's melted into a nap.
            let slow = sin(t * 1.1)
            sx = 1.05 + 0.035 * slow
            sy = 0.93 - 0.035 * slow
            wobble = 0.6
            flow = 0.45
        case .working:
            tilt = sin(t * 0.9) * 3
            wobble = 1.0
            flow = 1.0
        case .needsInput:
            let hop = abs(sin(t * 4.2))
            lift = -hop * 8
            sy = 1 - (1 - hop) * 0.07
            sx = 1 + (1 - hop) * 0.07
            tilt = sin(t * 7) * (since < 1.5 ? 6 : 3)
            shadow = 1 - hop * 0.15
            wobble = 1.4
            flow = 1.6
        case .done:
            if since < 2.6 {
                let hop = abs(sin(t * 5.6))
                lift = -hop * 28
                // Squash on landing, stretch in the air.
                sy = 1 - (1 - hop) * 0.16 + hop * 0.05
                sx = 1 + (1 - hop) * 0.16 - hop * 0.04
                shadow = 1 - hop * 0.35
                wobble = 1.9
                flow = 2.0
            } else {
                wobble = 1.2
                flow = 1.2
            }
            tilt = sin(t * 3) * 3
        }

        // Waking up: a big stretch and a jiggle.
        if justWoke && since < 0.7 {
            let s = sin(since / 0.7 * .pi)
            sy *= 1 + 0.16 * s
            sx *= 1 - 0.10 * s
            wobble += 1.5 * s
        }
    }
}

// MARK: - Liquid shape

/// An ellipse whose edge ripples like liquid. `t` is time; `amount` scales the ripples.
struct LiquidShape: Shape, Equatable {
    var t: Double
    var amount: Double

    func path(in rect: CGRect) -> Path {
        let n = 72
        let cx = rect.midX, cy = rect.midY
        let rx = rect.width / 2, ry = rect.height / 2
        var points: [CGPoint] = []
        points.reserveCapacity(n)
        for i in 0..<n {
            let a = Double(i) / Double(n) * 2 * .pi
            let ripple = 0.022 * sin(3 * a + 1.7 * t)
                + 0.016 * sin(2 * a - 1.3 * t + 1.0)
                + 0.010 * sin(5 * a + 2.3 * t + 2.0)
            let k = 1 + ripple * amount
            var y = sin(a)
            if y > 0 { y *= 0.96 } // a slightly heavier, flatter bottom, like a droplet resting
            points.append(CGPoint(x: cx + rx * k * cos(a), y: cy + ry * k * y))
        }
        // Smooth closed curve through the points (Catmull-Rom → cubic Bézier).
        var path = Path()
        path.move(to: points[0])
        for i in 0..<n {
            let p0 = points[(i - 1 + n) % n], p1 = points[i]
            let p2 = points[(i + 1) % n], p3 = points[(i + 2) % n]
            let c1 = CGPoint(x: p1.x + (p2.x - p0.x) / 6, y: p1.y + (p2.y - p0.y) / 6)
            let c2 = CGPoint(x: p2.x - (p3.x - p1.x) / 6, y: p2.y - (p3.y - p1.y) / 6)
            path.addCurve(to: p2, control1: c1, control2: c2)
        }
        path.closeSubpath()
        return path
    }
}

// MARK: - The glass blob

struct BlobView: View {
    let mood: Mood
    let t: Double
    let pose: Pose
    let calm: Bool
    let lookX: CGFloat
    let blink: Bool

    var body: some View {
        // While calm the glass is frozen, so SwiftUI can skip redrawing it entirely.
        let shape = LiquidShape(t: calm ? 0 : t * pose.flow, amount: pose.wobble)

        ZStack {
            GlassBody(shape: shape, t: t).equatable()
            FaceView(mood: mood, t: t, lookX: lookX, blink: blink)
        }
        .frame(width: 120, height: 104)
        .overlay(alignment: .topTrailing) {
            if mood == .needsInput {
                // A little waving glass nub.
                Ellipse()
                    .fill(PipColors.tintTop.opacity(0.55))
                    .overlay(Ellipse().stroke(Color.white.opacity(0.8), lineWidth: 1.2))
                    .frame(width: 20, height: 24)
                    .rotationEffect(.degrees(sin(t * 12) * 25), anchor: .bottom)
                    .offset(x: -16, y: 14)
            }
        }
        .scaleEffect(x: pose.sx, y: pose.sy, anchor: .bottom)
        .rotationEffect(.degrees(pose.tilt), anchor: .bottom)
        .frame(width: 128, height: 112, alignment: .bottom)
    }
}

/// Layers that make a translucent, liquid-glass body.
struct GlassBody: View, Equatable {
    let shape: LiquidShape
    let t: Double

    var body: some View {
        ZStack {
            // 1. Real background blur/refraction from the system (on-screen only).
            if PipRender.useSystemGlass {
                SystemGlass(shape: shape)
            }

            // Layers 2–7 are flattened into one GPU texture per frame; much cheaper to draw.
            ZStack {
            // 2. A soft tint so Pip reads as a body, not a hole.
            shape.fill(LinearGradient(colors: [PipColors.tintTop.opacity(0.42),
                                               PipColors.tintBottom.opacity(0.55)],
                                      startPoint: .top, endPoint: .bottom))

            // 3. Light pooling at the bottom, like light passing through a droplet.
            shape.fill(RadialGradient(colors: [Color.white.opacity(0.75), Color.white.opacity(0)],
                                      center: UnitPoint(x: 0.5, y: 0.92),
                                      startRadius: 2, endRadius: 52))

            // 4. Darker inner edge gives the glass thickness.
            shape.stroke(Color(red: 0.25, green: 0.22, blue: 0.45).opacity(0.28), lineWidth: 7)
                .blur(radius: 4)
                .mask(shape)

            // 5. A faint rainbow fringe at the edge (dispersion).
            shape.stroke(AngularGradient(colors: [.pink, .orange, .yellow, .mint, .cyan, .purple, .pink],
                                         center: .center, angle: .degrees(t * 20)),
                         lineWidth: 3)
                .blur(radius: 2)
                .opacity(0.35)
                .mask(shape)

            // 6. Crisp rim light: bright top-left, softer bottom-right.
            shape.stroke(AngularGradient(stops: [
                .init(color: .white.opacity(0.95), location: 0.00),
                .init(color: .white.opacity(0.25), location: 0.20),
                .init(color: .white.opacity(0.70), location: 0.45),
                .init(color: .white.opacity(0.20), location: 0.70),
                .init(color: .white.opacity(0.95), location: 1.00),
            ], center: .center, angle: .degrees(200)), lineWidth: 1.6)

            // 7. Specular highlights.
            Ellipse()
                .fill(LinearGradient(colors: [.white.opacity(0.95), .white.opacity(0.35)],
                                     startPoint: .top, endPoint: .bottom))
                .frame(width: 36, height: 15)
                .rotationEffect(.degrees(-24))
                .offset(x: -26, y: -30)
                .blur(radius: 0.6)
            Circle()
                .fill(Color.white.opacity(0.9))
                .frame(width: 6, height: 6)
                .offset(x: -6, y: -40)
            }
            .drawingGroup()
        }
    }
}

/// The system Liquid Glass material on macOS 26+, falling back to a behind-window blur.
struct SystemGlass: View {
    let shape: LiquidShape

    var body: some View {
        // glassEffect only exists in the macOS 26 SDK (Xcode 26 / Swift 6.2). Older
        // toolchains, e.g. on macOS 13–14, compile the blur fallback instead.
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) {
            Color.clear.glassEffect(.clear, in: shape)
        } else {
            BehindWindowBlur().mask(shape)
        }
        #else
        BehindWindowBlur().mask(shape)
        #endif
    }
}

struct BehindWindowBlur: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

// MARK: - Sleeping Zs (snapshots only)

/// On screen the Zs are Core Animation layers (SleepyZView). Snapshots can't capture those,
/// so this draws them at the same window positions, frozen at three points of their path.
struct SnapshotZs: View {
    var body: some View {
        let h = PipView.windowSize.height
        ZStack {
            ForEach([0.2, 0.5, 0.8], id: \.self) { p in
                Text("z")
                    .font(.system(size: 15 * (0.85 + 0.65 * p), weight: .heavy, design: .rounded))
                    .foregroundColor(PipColors.sleepZ)
                    .shadow(color: .white.opacity(0.9), radius: 1.5)
                    .position(x: SleepyZView.start.x + SleepyZView.rise.x * p,
                              y: h - (SleepyZView.start.y + SleepyZView.rise.y * p))
            }
        }
        .frame(width: PipView.windowSize.width, height: h)
    }
}

// MARK: - Face

struct FaceView: View {
    let mood: Mood
    let t: Double
    let lookX: CGFloat
    let blink: Bool

    private var blinking: Bool { PipRender.allowBlink && blink }

    var body: some View {
        ZStack {
            HStack(spacing: 50) { cheek; cheek }
                .offset(y: 12)

            HStack(spacing: 26) { eye; eye }
                .offset(x: mood == .working ? lookX : 0, y: -6)

            mouth.offset(y: 16)
        }
    }

    private var cheek: some View {
        Ellipse().fill(PipColors.cheek.opacity(0.4)).frame(width: 15, height: 9).blur(radius: 1)
    }

    @ViewBuilder private var eye: some View {
        switch mood {
        case .sleeping, .hidden:
            // Closed, peaceful eyes.
            SmileArc()
                .stroke(PipColors.face, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .frame(width: 13, height: 4)
        case .done:
            HappyEye()
                .stroke(PipColors.face, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .frame(width: 15, height: 8)
        case .needsInput:
            ZStack {
                Circle().fill(PipColors.face).frame(width: 17, height: 17)
                Circle().fill(Color.white).frame(width: 6, height: 6).offset(x: 3, y: -3)
            }
            .scaleEffect(y: blinking ? 0.1 : 1)
        case .working:
            ZStack {
                Capsule().fill(PipColors.face).frame(width: 11, height: 16)
                Circle().fill(Color.white).frame(width: 4, height: 4).offset(x: 2, y: -4)
            }
            .scaleEffect(y: blinking ? 0.1 : 1)
        }
    }

    @ViewBuilder private var mouth: some View {
        switch mood {
        case .sleeping, .hidden:
            // Tiny mouth that opens a little with each breath.
            Ellipse()
                .fill(PipColors.face.opacity(0.85))
                .frame(width: 6, height: 3 + 2 * (sin(t * 1.1) + 1) / 2)
        case .done:
            OpenSmile()
                .fill(PipColors.face)
                .overlay(
                    Ellipse().fill(PipColors.cheek).frame(width: 10, height: 6).offset(y: 3)
                        .mask(OpenSmile())
                )
                .frame(width: 22, height: 12)
        case .needsInput:
            Ellipse().fill(PipColors.face).frame(width: 9, height: 11)
        case .working:
            SmileArc()
                .stroke(PipColors.face, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .frame(width: 13, height: 5)
        }
    }
}

struct HappyEye: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.maxY))
        p.addQuadCurve(to: CGPoint(x: r.maxX, y: r.maxY),
                       control: CGPoint(x: r.midX, y: r.minY - r.height * 0.7))
        return p
    }
}

struct SmileArc: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.minY))
        p.addQuadCurve(to: CGPoint(x: r.maxX, y: r.minY),
                       control: CGPoint(x: r.midX, y: r.maxY + r.height * 0.8))
        return p
    }
}

struct OpenSmile: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.minY))
        p.addQuadCurve(to: CGPoint(x: r.minX, y: r.minY),
                       control: CGPoint(x: r.midX, y: r.maxY + r.height * 0.9))
        p.closeSubpath()
        return p
    }
}

// MARK: - Confetti

struct ConfettiView: View {
    let started: Date
    let now: Date
    private let duration = 3.0

    var body: some View {
        Canvas { context, size in
            let elapsed = now.timeIntervalSince(started)
            guard elapsed >= 0, elapsed < duration else { return }
            var rng = SplitMix64(seed: UInt64(started.timeIntervalSince1970 * 1000))
            let origin = CGPoint(x: size.width / 2, y: size.height - 135) // just above Pip's head
            let gravity = 520.0

            for i in 0..<60 {
                let angle = Double.random(in: (-Double.pi * 0.92)...(-Double.pi * 0.08), using: &rng)
                let speed = Double.random(in: 170...360, using: &rng)
                let spin = Double.random(in: -12...12, using: &rng)
                let x = origin.x + cos(angle) * speed * elapsed
                let y = origin.y + sin(angle) * speed * elapsed + 0.5 * gravity * elapsed * elapsed

                var piece = context
                piece.opacity = max(0, 1 - elapsed / duration)
                piece.translateBy(x: x, y: y)
                piece.rotate(by: .radians(spin * elapsed))
                piece.fill(Path(CGRect(x: -4, y: -2.5, width: 8, height: 5)),
                           with: .color(PipColors.confetti[i % PipColors.confetti.count]))
            }
        }
        .allowsHitTesting(false)
    }
}

struct SplitMix64: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
