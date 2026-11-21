import AppKit
import SwiftUI

/// `Pip --snapshot <dir>` renders each mood to a PNG (plus one sheet with all of them) and exits.
/// The system glass blur only exists on screen, so snapshots show the drawn glass layers
/// over a colorful backdrop to make the transparency visible.
@MainActor
enum Snapshot {
    static func run(into dir: String) {
        PipRender.useSystemGlass = false
        PipRender.allowBlink = false
        let cases: [(String, PipEvent)] = [
            ("sleeping", PipEvent(state: "sleep", source: "", message: nil)),
            ("working", PipEvent(state: "working", source: "claude", message: nil)),
            ("needs-input", PipEvent(state: "needs-input", source: "claude",
                                     message: "Claude needs your permission to use Bash")),
            ("done", PipEvent(state: "done", source: "cursor", message: "We shipped something!")),
        ]

        var tiles: [(String, PipModel)] = []
        for (name, event) in cases {
            let model = PipModel()
            model.silent = true
            model.handle(event)
            tiles.append((name, model))
            write(PipView(model: model).background(Backdrop()), to: dir, name: name)
        }

        let sheet = HStack(spacing: 0) {
            ForEach(tiles, id: \.0) { name, model in
                VStack(spacing: 0) {
                    PipView(model: model)
                    Text(name.replacingOccurrences(of: "-", with: " ").capitalized)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundColor(.white)
                        .padding(.bottom, 12)
                }
            }
        }
        .background(Backdrop())
        write(sheet, to: dir, name: "all-poses")
    }

    private static func write<V: View>(_ view: V, to dir: String, name: String) {
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        guard let image = renderer.nsImage, let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else { return }
        let url = URL(fileURLWithPath: dir).appendingPathComponent("\(name).png")
        try? png.write(to: url)
        print(url.path)
    }
}

/// A wallpaper-like backdrop so the glass has something to show through.
private struct Backdrop: View {
    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.36, green: 0.30, blue: 0.62),
                                    Color(red: 0.95, green: 0.55, blue: 0.45)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            GeometryReader { geo in
                ForEach(0..<Int(geo.size.width / 75), id: \.self) { i in
                    Circle()
                        .fill(i % 2 == 0 ? Color.yellow.opacity(0.55) : Color.cyan.opacity(0.5))
                        .frame(width: 70, height: 70)
                        .position(x: CGFloat(i) * 75 + 40, y: geo.size.height - 70 + (i % 3 == 0 ? -25 : 15))
                }
            }
        }
    }
}
