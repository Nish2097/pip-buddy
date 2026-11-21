import AppKit
import SwiftUI

/// `Pip --snapshot <dir>` renders each mood to a PNG (plus one sheet with all of them) and exits.
/// Images have a transparent background so they sit nicely on any page (light or dark).
/// The system glass blur only exists on screen, so snapshots show the drawn glass layers.
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
            write(PipView(model: model), to: dir, name: name)
        }

        let sheet = HStack(spacing: 0) {
            ForEach(tiles, id: \.0) { name, model in
                VStack(spacing: 0) {
                    // Trim the empty space above the tallest speech bubble.
                    PipView(model: model)
                        .frame(height: 215, alignment: .bottom)
                        .clipped()
                    Text(name.replacingOccurrences(of: "-", with: " ").capitalized)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundColor(Color(white: 0.5)) // readable on light and dark pages
                        .padding(.top, 6)
                        .padding(.bottom, 8)
                }
            }
        }
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
