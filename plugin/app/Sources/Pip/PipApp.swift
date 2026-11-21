import AppKit
import SwiftUI

let pipPort: UInt16 = UInt16(ProcessInfo.processInfo.environment["PIP_PORT"] ?? "") ?? 47823

@main
enum PipMain {
    static func main() {
        MainActor.assumeIsolated {
            let args = CommandLine.arguments
            if let i = args.firstIndex(of: "--snapshot"), i + 1 < args.count {
                Snapshot.run(into: args[i + 1])
                return
            }
            let app = NSApplication.shared
            let delegate = AppDelegate()
            app.delegate = delegate
            app.setActivationPolicy(.accessory) // menu bar only, no Dock icon
            withExtendedLifetime(delegate) { app.run() }
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let model = PipModel()
    private var panel: NSPanel!
    private var statusItem: NSStatusItem!
    private var server: EventServer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        setUpPanel()
        setUpMenu()
        startServer()

        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.positionPanel() }
        }

        model.handle(PipEvent(state: "done", source: "Pip",
                              message: "Hi, I'm Pip! I'll nap here and wake up when your agent needs you."))
    }

    // MARK: Floating window

    private func setUpPanel() {
        let size = PipView.windowSize
        panel = NSPanel(contentRect: NSRect(origin: .zero, size: size),
                        styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.isMovable = false
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false

        // Container: the SwiftUI view, plus a Core Animation layer for the sleepy Zs on top.
        let container = NSView(frame: NSRect(origin: .zero, size: size))
        container.wantsLayer = true
        let host = NSHostingView(rootView: PipView(model: model))
        host.frame = container.bounds
        host.autoresizingMask = [.width, .height]
        host.wantsLayer = true
        container.addSubview(host)
        container.addSubview(zView)
        hostView = host
        panel.contentView = container

        model.onInteractiveChange = { [weak self] clickable in
            self?.panel.ignoresMouseEvents = !clickable
        }
        model.onMoodChange = { [weak self] _ in self?.updateIdleAnimations() }
        updateIdleAnimations()

        positionPanel()
        panel.orderFrontRegardless()
    }

    private var hostView: NSView?
    private let zView = SleepyZView(frame: NSRect(origin: .zero, size: PipView.windowSize))

    /// Breathing and floating Zs for calm moods. These run in Core Animation in the
    /// window server, so the app itself does almost no work while Pip idles.
    private func updateIdleAnimations() {
        let mood = model.mood
        zView.isAnimating = mood == .sleeping

        guard let layer = hostView?.layer else { return }
        layer.removeAnimation(forKey: "breathe")
        let style: (amount: CGFloat, halfPeriod: Double)? = switch mood {
        case .sleeping: (0.035, 2.8)
        case .working where model.isCalm: (0.022, 1.4)
        default: nil
        }
        guard let style else { return }

        // Scale around the bottom-center of the window, wherever the layer's anchor is.
        let pivotX = layer.bounds.width * (0.5 - layer.anchorPoint.x)
        let pivotY = layer.bounds.height * (0 - layer.anchorPoint.y)
        func breath(_ k: CGFloat) -> NSValue {
            var m = CATransform3DMakeTranslation(pivotX, pivotY, 0)
            m = CATransform3DScale(m, 1 - k * 0.8, 1 + k, 1)
            m = CATransform3DTranslate(m, -pivotX, -pivotY, 0)
            return NSValue(caTransform3D: m)
        }
        let anim = CABasicAnimation(keyPath: "transform")
        anim.fromValue = breath(-style.amount)
        anim.toValue = breath(style.amount)
        anim.duration = style.halfPeriod
        anim.autoreverses = true
        anim.repeatCount = .infinity
        anim.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        layer.add(anim, forKey: "breathe")
    }

    private func positionPanel() {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let visible = screen.visibleFrame
        let size = PipView.windowSize
        panel.setFrameOrigin(NSPoint(x: visible.maxX - size.width - 12, y: visible.minY))
    }

    // MARK: Menu bar

    private func setUpMenu() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "face.smiling", accessibilityDescription: "Pip")
        }
        rebuildMenu()
    }

    private func rebuildMenu() {
        let menu = NSMenu()
        let header = NSMenuItem(title: "Pip is listening on port \(pipPort)", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        menu.addItem(.separator())

        let mute = NSMenuItem(title: "Mute Sounds", action: #selector(toggleMute), keyEquivalent: "")
        mute.target = self
        mute.state = model.muted ? .on : .off
        menu.addItem(mute)

        let hide = NSMenuItem(title: "Hide While Sleeping", action: #selector(toggleHideWhenSleeping), keyEquivalent: "")
        hide.target = self
        hide.state = model.hideWhenSleeping ? .on : .off
        menu.addItem(hide)

        menu.addItem(.separator())
        let test = NSMenuItem(title: "Try an Animation", action: nil, keyEquivalent: "")
        let sub = NSMenu()
        for (title, state) in [("Working", "working"), ("Needs You", "needs-input"), ("Done", "done"), ("Sleep", "sleep")] {
            let item = NSMenuItem(title: title, action: #selector(tryAnimation(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = state
            sub.addItem(item)
        }
        test.submenu = sub
        menu.addItem(test)

        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit Pip", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)
        statusItem.menu = menu
    }

    @objc private func toggleMute() { model.muted.toggle(); rebuildMenu() }
    @objc private func toggleHideWhenSleeping() { model.hideWhenSleeping.toggle(); rebuildMenu() }
    @objc private func tryAnimation(_ sender: NSMenuItem) {
        guard let state = sender.representedObject as? String else { return }
        let message = state == "needs-input" ? "Claude needs your permission to use Bash" : nil
        model.handle(PipEvent(state: state, source: "Pip", message: message))
    }

    // MARK: Event server

    private func startServer() {
        do {
            let server = try EventServer(port: pipPort) { [weak self] event in
                Task { @MainActor in self?.model.handle(event) }
            }
            server.start { error in
                // Most likely another Pip is already running on this port.
                NSLog("Pip: event server failed: \(error). Quitting.")
                DispatchQueue.main.async { NSApp.terminate(nil) }
            }
            self.server = server
        } catch {
            NSLog("Pip: could not create event server: \(error)")
        }
    }
}
