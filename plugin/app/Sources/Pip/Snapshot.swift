import AppKit
import SwiftUI

/// `Pip --snapshot <dir>` renders each mood to a PNG and exits.
/// Handy for checking art changes and making README images.
@MainActor
enum Snapshot {
    static func run(into dir: String) {
        let cases: [(String, PipEvent)] = [
            ("working", PipEvent(state: "working", source: "claude", message: nil)),
            ("needs-input", PipEvent(state: "needs-input", source: "claude",
                                     message: "Claude needs your permission to use Bash")),
            ("done", PipEvent(state: "done", source: "cursor", message: "We shipped something!")),
        ]
        for (name, event) in cases {
            let model = PipModel()
            model.silent = true
            model.handle(event)
            let view = PipView(model: model).background(Color(white: 0.88))
            let renderer = ImageRenderer(content: view)
            renderer.scale = 2
            guard let image = renderer.nsImage, let tiff = image.tiffRepresentation,
                  let rep = NSBitmapImageRep(data: tiff),
                  let png = rep.representation(using: .png, properties: [:]) else { continue }
            let url = URL(fileURLWithPath: dir).appendingPathComponent("\(name).png")
            try? png.write(to: url)
            print(url.path)
        }
    }
}
