import AppKit
import SwiftUI

enum Mood: Equatable {
    case hidden      // tucked away below the screen edge
    case working     // peeking up, eyes looking around
    case needsInput  // popped up, waving for attention
    case done        // popped up, jumping with confetti
}

@MainActor
final class PipModel: ObservableObject {
    @Published private(set) var mood: Mood = .hidden
    @Published private(set) var message = ""
    @Published private(set) var source = ""
    /// When the current mood started; drives one-off animations like confetti.
    @Published private(set) var moodStarted = Date()

    /// Called when the mascot becomes clickable (popped up) or not.
    var onInteractiveChange: ((Bool) -> Void)?

    var muted: Bool {
        get { UserDefaults.standard.bool(forKey: "muted") }
        set { UserDefaults.standard.set(newValue, forKey: "muted") }
    }

    var peekWhileWorking: Bool {
        get { UserDefaults.standard.object(forKey: "peekWhileWorking") as? Bool ?? true }
        set {
            UserDefaults.standard.set(newValue, forKey: "peekWhileWorking")
            if mood == .working && !newValue { set(.hidden) }
        }
    }

    private var hideTask: Task<Void, Never>?

    private let doneLines = [
        "Hey! Your task is complete.",
        "We shipped something!",
        "Done! You can take a break now.",
        "All yours again.",
        "Build's done. High five!",
        "Finished! Come take a look.",
    ]

    func handle(_ event: PipEvent) {
        source = Self.displayName(for: event.source)
        switch event.state {
        case "working":
            guard peekWhileWorking else { set(.hidden); return }
            guard mood != .working else { return } // fires on every tool call; no need to restart
            message = ""
            set(.working)
        case "needs-input":
            message = event.message ?? "I need you for a sec!"
            set(.needsInput)
            play("Funk")
        case "done":
            message = event.message ?? doneLines.randomElement()!
            set(.done)
            play("Glass")
            hide(after: 6)
        case "hide", "idle":
            set(.hidden)
        default:
            break
        }
    }

    func dismiss() { set(.hidden) }

    private func set(_ newMood: Mood) {
        hideTask?.cancel()
        hideTask = nil
        mood = newMood
        moodStarted = Date()
        onInteractiveChange?(newMood == .needsInput || newMood == .done)
    }

    private func hide(after seconds: Double) {
        hideTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.set(.hidden)
        }
    }

    /// Skips sounds (used when rendering snapshots).
    var silent = false

    private func play(_ name: String) {
        guard !muted, !silent else { return }
        NSSound(named: NSSound.Name(name))?.play()
    }

    private static func displayName(for source: String) -> String {
        switch source.lowercased() {
        case "claude", "claude-code": return "Claude Code"
        case "cursor": return "Cursor"
        case "codex": return "Codex"
        case "": return ""
        default: return source
        }
    }
}
