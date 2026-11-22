import AppKit
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

/// `Pip --demo <file.gif> [--background light|black] [--scale 2] [--fps 20]`
/// renders a looping demo: napping → working → needs you → done → napping.
/// Every frame is drawn at a fixed moment, so the result is smooth and identical every time.
@MainActor
enum DemoVideo {
    enum Background: String { case light, black }

    struct Options {
        var background = Background.light
        var scale: CGFloat = 2
        var fps = 20.0

        init(arguments: [String]) {
            func value(_ flag: String) -> String? {
                guard let i = arguments.firstIndex(of: flag), i + 1 < arguments.count else { return nil }
                return arguments[i + 1]
            }
            if let b = value("--background").flatMap(Background.init(rawValue:)) { background = b }
            if let s = value("--scale").flatMap(Double.init) { scale = CGFloat(s) }
            if let f = value("--fps").flatMap(Double.init) { fps = f }
        }
    }

    /// One step of the story: which event fires, and when (seconds from the start).
    private struct Beat {
        let at: Double
        let state: String
        let source: String
        let message: String?
    }

    private static let beats: [Beat] = [
        Beat(at: 0.0, state: "sleep", source: "", message: nil),
        Beat(at: 2.2, state: "working", source: "claude", message: nil),
        Beat(at: 4.6, state: "needs-input", source: "claude",
             message: "Claude needs your permission to run the tests"),
        Beat(at: 7.0, state: "working", source: "claude", message: nil),
        Beat(at: 8.2, state: "done", source: "claude", message: "We shipped something!"),
        Beat(at: 11.2, state: "sleep", source: "", message: nil),
    ]
    private static let duration = 12.8
    private static let napDepth: CGFloat = 42

    static func render(to path: String, options: Options) {
        let fps = options.fps
        PipRender.useSystemGlass = false
        PipRender.allowBlink = true
        PipRender.darkBackdrop = options.background == .black

        let model = PipModel()
        model.silent = true
        let start = Date(timeIntervalSinceReferenceDate: 1_000_000)
        var clock = start
        model.now = { clock }

        let frameCount = Int(duration * fps)
        let url = URL(fileURLWithPath: path) as CFURL
        guard let gif = CGImageDestinationCreateWithURL(url, UTType.gif.identifier as CFString, frameCount, nil) else {
            print("Can't write \(path)"); return
        }
        CGImageDestinationSetProperties(gif, [
            kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0],
        ] as CFDictionary)
        let frameProps = [
            kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 1.0 / fps],
        ] as CFDictionary

        var nextBeat = 0
        for frame in 0..<frameCount {
            let time = Double(frame) / fps
            clock = start.addingTimeInterval(time)
            PipRender.clock = clock

            while nextBeat < beats.count, beats[nextBeat].at <= time {
                let beat = beats[nextBeat]
                model.handle(PipEvent(state: beat.state, source: beat.source, message: beat.message))
                nextBeat += 1
            }
            PipRender.sinkOverride = sink(at: time)

            let view = ZStack(alignment: .bottom) {
                DemoBackdrop(style: options.background)
                PipView(model: model)
            }
            .frame(width: PipView.windowSize.width, height: 250, alignment: .bottom)
            .clipped()

            let renderer = ImageRenderer(content: view)
            renderer.scale = options.scale
            guard let image = renderer.cgImage else { continue }
            CGImageDestinationAddImage(gif, image, frameProps)
        }

        if CGImageDestinationFinalize(gif) {
            print("\(path) (\(frameCount) frames at \(Int(fps)) fps, \(String(format: "%.1f", duration)) s)")
        } else {
            print("Couldn't finish writing \(path)")
        }
    }

    /// Eases Pip up out of its nap and back down into it.
    private static func sink(at time: Double) -> CGFloat {
        let wake = 2.2, sleep = 11.2, rise = 0.45, fall = 0.7
        func easeOutBack(_ x: Double) -> Double {
            let c1 = 1.70158, c3 = c1 + 1
            return 1 + c3 * pow(x - 1, 3) + c1 * pow(x - 1, 2)
        }
        func easeInOut(_ x: Double) -> Double { x < 0.5 ? 2 * x * x : 1 - pow(-2 * x + 2, 2) / 2 }

        if time < wake { return napDepth }
        if time < wake + rise { return napDepth * CGFloat(1 - easeOutBack((time - wake) / rise)) }
        if time < sleep { return 0 }
        if time < sleep + fall { return napDepth * CGFloat(easeInOut((time - sleep) / fall)) }
        return napDepth
    }
}

/// A soft desktop-like backdrop so the glass reads well once X converts the GIF to video.
private struct DemoBackdrop: View {
    let style: DemoVideo.Background

    var body: some View {
        switch style {
        case .light:
            LinearGradient(colors: [Color(red: 0.93, green: 0.92, blue: 0.99),
                                    Color(red: 0.99, green: 0.91, blue: 0.88)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
        case .black:
            Color.black
        }
    }
}
