import SwiftUI

// MARK: - Palette

enum PipColors {
    static let top = Color(red: 1.00, green: 0.62, blue: 0.47)
    static let bottom = Color(red: 0.96, green: 0.40, blue: 0.42)
    static let face = Color(red: 0.20, green: 0.12, blue: 0.16)
    static let cheek = Color(red: 1.00, green: 0.42, blue: 0.55)
    static let accent = Color(red: 0.90, green: 0.36, blue: 0.36)
    static let confetti: [Color] = [
        Color(red: 1.00, green: 0.78, blue: 0.20),
        Color(red: 0.35, green: 0.78, blue: 0.98),
        Color(red: 0.55, green: 0.88, blue: 0.45),
        Color(red: 0.98, green: 0.45, blue: 0.62),
        Color(red: 0.70, green: 0.55, blue: 1.00),
    ]
}

// MARK: - Root view (fills the floating window)

struct PipView: View {
    @ObservedObject var model: PipModel

    static let windowSize = CGSize(width: 300, height: 320)

    private var showsBubble: Bool { model.mood == .needsInput || model.mood == .done }

    private var blobOffset: CGFloat {
        switch model.mood {
        case .hidden: return 190      // fully below the window edge
        case .working: return 72      // just the top half peeks up
        case .needsInput, .done: return 0
        }
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            if model.mood == .done {
                ConfettiView(started: model.moodStarted)
            }
            VStack(spacing: 10) {
                if showsBubble {
                    SpeechBubble(source: model.source, message: model.message)
                        .padding(.bottom, model.mood == .done ? 30 : 0) // room for the jump
                        .transition(.scale(scale: 0.6, anchor: .bottom).combined(with: .opacity))
                        .id(model.moodStarted)
                }
                BlobView(mood: model.mood, moodStarted: model.moodStarted)
                    .frame(width: 150, height: 140)
                    .offset(y: blobOffset)
            }
        }
        .frame(width: Self.windowSize.width, height: Self.windowSize.height, alignment: .bottom)
        .clipped()
        .contentShape(Rectangle())
        .onTapGesture { model.dismiss() }
        .animation(.spring(response: 0.5, dampingFraction: 0.62), value: model.mood)
        .animation(.spring(response: 0.5, dampingFraction: 0.62), value: model.moodStarted)
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

// MARK: - The blob

struct BlobView: View {
    let mood: Mood
    let moodStarted: Date

    var body: some View {
        TimelineView(.animation) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            let since = timeline.date.timeIntervalSince(moodStarted)
            let pose = Pose(mood: mood, t: t, since: since)

            ZStack(alignment: .bottom) {
                // Ground shadow shrinks as the blob jumps.
                Ellipse()
                    .fill(Color.black.opacity(0.16))
                    .frame(width: 92 * pose.shadow, height: 12)
                    .blur(radius: 2.5)

                ZStack {
                    Ellipse()
                        .fill(LinearGradient(colors: [PipColors.top, PipColors.bottom],
                                             startPoint: .top, endPoint: .bottom))
                    Ellipse()
                        .fill(Color.white.opacity(0.35))
                        .frame(width: 34, height: 17)
                        .rotationEffect(.degrees(-22))
                        .offset(x: -27, y: -28)
                    FaceView(mood: mood, t: t)
                }
                .frame(width: 120, height: 104)
                .overlay(alignment: .topTrailing) {
                    if mood == .needsInput {
                        // A little waving nub.
                        Ellipse()
                            .fill(PipColors.top)
                            .frame(width: 22, height: 26)
                            .rotationEffect(.degrees(sin(t * 12) * 25), anchor: .bottom)
                            .offset(x: -6, y: 6)
                    }
                }
                .scaleEffect(x: pose.sx, y: pose.sy, anchor: .bottom)
                .rotationEffect(.degrees(pose.tilt), anchor: .bottom)
                .offset(y: pose.lift - 5)
            }
        }
    }
}

/// Body transform for the current moment.
struct Pose {
    var sx = 1.0, sy = 1.0, tilt = 0.0, lift = 0.0, shadow = 1.0

    init(mood: Mood, t: Double, since: Double) {
        let breathe = sin(t * 2.2)
        sx = 1 + 0.03 * breathe
        sy = 1 - 0.03 * breathe

        switch mood {
        case .hidden:
            break
        case .working:
            tilt = sin(t * 0.9) * 3
        case .needsInput:
            let hop = abs(sin(t * 4.2))
            lift = -hop * 9
            sy = 1 - (1 - hop) * 0.07
            sx = 1 + (1 - hop) * 0.07
            tilt = sin(t * 7) * (since < 1.5 ? 6 : 3)
            shadow = 1 - hop * 0.15
        case .done:
            if since < 2.6 {
                let hop = abs(sin(t * 5.6))
                lift = -hop * 30
                sy = 1 - (1 - hop) * 0.14 + hop * 0.04
                sx = 1 + (1 - hop) * 0.14 - hop * 0.03
                shadow = 1 - hop * 0.35
            }
            tilt = sin(t * 3) * 3
        }
    }
}

// MARK: - Face

struct FaceView: View {
    let mood: Mood
    let t: Double

    private var blinking: Bool { t.truncatingRemainder(dividingBy: 3.8) < 0.13 }

    var body: some View {
        ZStack {
            // Cheeks
            HStack(spacing: 50) {
                cheek
                cheek
            }
            .offset(y: 12)

            // Eyes
            HStack(spacing: 26) {
                eye
                eye
            }
            .offset(x: mood == .working ? sin(t * 0.7) * 7 : 0, y: -6)

            mouth.offset(y: 16)
        }
    }

    private var cheek: some View {
        Ellipse().fill(PipColors.cheek.opacity(0.45)).frame(width: 15, height: 9)
    }

    @ViewBuilder private var eye: some View {
        switch mood {
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
        case .working, .hidden:
            ZStack {
                Capsule().fill(PipColors.face).frame(width: 11, height: 16)
                Circle().fill(Color.white).frame(width: 4, height: 4).offset(x: 2, y: -4)
            }
            .scaleEffect(y: blinking ? 0.1 : 1)
        }
    }

    @ViewBuilder private var mouth: some View {
        switch mood {
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
        case .working, .hidden:
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
    private let duration = 3.0

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, size in
                let elapsed = timeline.date.timeIntervalSince(started)
                guard elapsed >= 0, elapsed < duration else { return }
                var rng = SplitMix64(seed: UInt64(started.timeIntervalSince1970 * 1000))
                let origin = CGPoint(x: size.width / 2, y: size.height - 80)
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
