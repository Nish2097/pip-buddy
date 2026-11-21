import AppKit
import SwiftUI

enum Mood: Equatable {
    case sleeping    // idle: dozing in the corner
    case working     // awake, eyes looking around
    case needsInput  // waving for attention
    case done        // jumping with confetti
    case hidden      // only when "Hide While Sleeping" is on
}

@MainActor
final class PipModel: ObservableObject {
    @Published private(set) var mood: Mood = .sleeping
    @Published private(set) var message = ""
    @Published private(set) var source = ""
    /// When the current mood started; drives one-off animations (wake-up stretch, confetti).
    @Published private(set) var moodStarted = Date()
    /// True when this mood began by waking up from sleep.
    @Published private(set) var justWoke = false
    /// True once the opening animation of a mood is over and Pip can idle cheaply.
    @Published private(set) var settled = false

    /// Calm moods are drawn once and animated only by Core Animation (near-zero CPU).
    var isCalm: Bool { mood == .sleeping || mood == .hidden || settled }

    /// Called when Pip becomes clickable (bubble showing) or not.
    var onInteractiveChange: ((Bool) -> Void)?
    /// Called whenever the mood changes.
    var onMoodChange: ((Mood) -> Void)?

    /// Skips sounds (used when rendering snapshots).
    var silent = false

    var muted: Bool {
        get { UserDefaults.standard.bool(forKey: "muted") }
        set { UserDefaults.standard.set(newValue, forKey: "muted") }
    }

    var hideWhenSleeping: Bool {
        get { UserDefaults.standard.bool(forKey: "hideWhenSleeping") }
        set {
            UserDefaults.standard.set(newValue, forKey: "hideWhenSleeping")
            if mood == .sleeping || mood == .hidden { rest() }
        }
    }

    private var timer: Task<Void, Never>?
    private var settleTimer: Task<Void, Never>?

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
            // Fires on every tool call: keep the current animation, just push back the nap.
            if mood != .working {
                message = ""
                set(.working)
            }
            // If the agent is interrupted, no "done" ever arrives. Doze off eventually.
            restAfter(seconds: 600)
        case "needs-input":
            message = event.message ?? "I need you for a sec!"
            set(.needsInput)
            play("Funk")
        case "done":
            message = event.message ?? doneLines.randomElement()!
            set(.done)
            play("Glass")
            restAfter(seconds: 6)
        case "hide", "idle", "sleep":
            rest()
        default:
            break
        }
    }

    /// Clicking Pip dismisses the bubble and sends it back to sleep.
    func dismiss() { rest() }

    private func rest() { set(hideWhenSleeping ? .hidden : .sleeping) }

    private func set(_ newMood: Mood) {
        timer?.cancel()
        timer = nil
        settleTimer?.cancel()
        settled = false
        justWoke = (mood == .sleeping || mood == .hidden) && newMood != .sleeping && newMood != .hidden
        mood = newMood
        moodStarted = Date()
        onInteractiveChange?(newMood == .needsInput || newMood == .done)
        onMoodChange?(newMood)

        // Working settles once the wake-up stretch is over; waiting for you settles after
        // a few seconds of waving. "Done" is short anyway, so it stays fully animated.
        let settleAfter: Double? = switch newMood {
        case .working: 1.0
        case .needsInput: 12
        default: nil
        }
        if let settleAfter {
            settleTimer = Task { [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(settleAfter * 1_000_000_000))
                guard let self, !Task.isCancelled else { return }
                withAnimation(.easeInOut(duration: 0.3)) { self.settled = true }
                self.onMoodChange?(self.mood)
            }
        }
    }

    private func restAfter(seconds: Double) {
        timer?.cancel()
        timer = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.rest()
        }
    }

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
