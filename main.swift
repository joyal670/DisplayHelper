import Cocoa

// Display Helper — a menu bar utility that keeps the display awake and the
// system marked active while you're away. Toggle from the menu bar.
//
// When ON, every CHECK_EVERY seconds it checks how long you've been idle;
// past IDLE_THRESHOLD it posts a no-op F15 keypress (does nothing on normal
// keyboards) to reset the system idle timer, and holds `caffeinate` so the
// display/system won't sleep. When OFF it does nothing.

let IDLE_THRESHOLD: Double = 240   // seconds idle before nudging (4 min)
let CHECK_EVERY: TimeInterval = 30 // how often to check (seconds)
let F15_KEYCODE: CGKeyCode = 113

final class AppController: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var toggleMenuItem: NSMenuItem!
    private var statusMenuItem: NSMenuItem!
    private var timer: Timer?
    private var caffeinate: Process?
    private var active = false
    /// Bumped whenever the caffeinate process is replaced or deliberately
    /// stopped, so a stale terminationHandler can tell it is stale.
    private var caffeinateGeneration = 0

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        // Neutral, monochrome menu bar glyph that adapts to light/dark.
        if let img = NSImage(systemSymbolName: "display",
                             accessibilityDescription: "Display Helper") {
            img.isTemplate = true
            statusItem.button?.image = img
        } else {
            statusItem.button?.title = "🖥"
        }

        let menu = NSMenu()
        statusMenuItem = NSMenuItem(title: "Status: Off", action: nil, keyEquivalent: "")
        statusMenuItem.isEnabled = false
        menu.addItem(statusMenuItem)
        menu.addItem(.separator())

        toggleMenuItem = NSMenuItem(
            title: "Keep Display Awake",
            action: #selector(toggle),
            keyEquivalent: "")
        toggleMenuItem.target = self
        menu.addItem(toggleMenuItem)

        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        statusItem.menu = menu
        render()
    }

    @objc private func toggle() {
        active ? stop() : start()
    }

    private func start() {
        active = true
        caffeinateGeneration += 1
        let generation = caffeinateGeneration

        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/caffeinate")
        // -w ties the assertion's lifetime to this process: caffeinate releases
        // it and exits by itself once we exit. Without it, a force-quit — which
        // never reaches stop() — leaves caffeinate reparented to launchd,
        // pinning the display awake with no UI left to switch it off.
        p.arguments = ["-dimsu", "-w", String(ProcessInfo.processInfo.processIdentifier)]
        // caffeinate can still be killed out from under us. Notice it rather
        // than carry on reporting a hold we no longer have.
        p.terminationHandler = { [weak self] _ in
            DispatchQueue.main.async {
                guard let self, self.active,
                      self.caffeinateGeneration == generation else { return }
                self.stop()
            }
        }

        do {
            try p.run()
            caffeinate = p
        } catch {
            // Nothing is holding the display awake, so do not claim otherwise.
            caffeinate = nil
            active = false
            render()
            return
        }

        let t = Timer(timeInterval: CHECK_EVERY, repeats: true) { [weak self] _ in
            self?.tick()
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
        render()
    }

    private func stop() {
        active = false
        // Invalidates any pending terminationHandler, so the terminate() below
        // is not mistaken for caffeinate dying unexpectedly.
        caffeinateGeneration += 1
        timer?.invalidate()
        timer = nil
        caffeinate?.terminate()
        caffeinate = nil
        render()
    }

    private func tick() {
        let idle = CGEventSource.secondsSinceLastEventType(
            .combinedSessionState, eventType: .init(rawValue: ~0)!)
        if idle >= IDLE_THRESHOLD {
            let src = CGEventSource(stateID: .hidSystemState)
            CGEvent(keyboardEventSource: src, virtualKey: F15_KEYCODE, keyDown: true)?
                .post(tap: .cghidEventTap)
            CGEvent(keyboardEventSource: src, virtualKey: F15_KEYCODE, keyDown: false)?
                .post(tap: .cghidEventTap)
        }
    }

    private func render() {
        // No color tell in the menu bar; state lives only in the dropdown.
        toggleMenuItem.state = active ? .on : .off
        statusMenuItem.title = active ? "Status: On" : "Status: Off"
    }

    @objc private func quit() {
        stop()
        NSApplication.shared.terminate(nil)
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let controller = AppController()
app.delegate = controller
app.run()
