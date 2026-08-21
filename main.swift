import Cocoa
import ApplicationServices

// Display Helper — a menu bar utility that keeps the display awake and the
// system marked active while you're away. Toggle from the menu bar.
//
// When ON, every CHECK_EVERY seconds it checks how long you've been idle;
// past IDLE_THRESHOLD it posts a no-op F15 keypress (does nothing on normal
// keyboards) to reset the system idle timer, and holds `caffeinate` so the
// display/system won't sleep. When OFF it does nothing.

// Tunable at runtime, so changing them needs no rebuild:
//
//   defaults write local.displayhelper idleThreshold -float 45
//   defaults write local.displayhelper checkEvery    -float 15
//
// That matters more than it looks. The ad-hoc signature is derived from the
// binary, so every rebuild is a new code identity and the Accessibility grant
// has to be removed and re-added. Reading these from UserDefaults means tuning
// never costs you the permission.
//
// The default is deliberately well below any plausible idle threshold in other
// software. Nudging at 240s let the idle timer peak around 255s, which loses a
// race against anything that reacts sooner.
let IDLE_THRESHOLD: Double =
    UserDefaults.standard.object(forKey: "idleThreshold") as? Double ?? 60
let CHECK_EVERY: TimeInterval =
    UserDefaults.standard.object(forKey: "checkEvery") as? Double ?? 20
let F15_KEYCODE: CGKeyCode = 113

final class AppController: NSObject, NSApplicationDelegate {
    /// Remembers the toggle across launches. Unset means on — the app is
    /// meant to be doing its job by default rather than waiting to be asked.
    private static let keepAwakeKey = "keepDisplayAwake"

    private var statusItem: NSStatusItem!
    private var toggleMenuItem: NSMenuItem!
    private var statusMenuItem: NSMenuItem!
    private var accessibilityMenuItem: NSMenuItem!
    private var timer: Timer?
    private var caffeinate: Process?
    private var active = false
    /// Bumped whenever the caffeinate process is replaced or deliberately
    /// stopped, so a stale terminationHandler can tell it is stale.
    private var caffeinateGeneration = 0

    func applicationDidFinishLaunching(_ notification: Notification) {
        // register(defaults:) rather than a plain read, so "never set" reads as
        // on without being confused with an explicit off.
        UserDefaults.standard.register(defaults: [Self.keepAwakeKey: true])

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

        accessibilityMenuItem = NSMenuItem(
            title: "Grant Accessibility Access…",
            action: #selector(openAccessibilitySettings),
            keyEquivalent: "")
        accessibilityMenuItem.target = self
        menu.addItem(accessibilityMenuItem)

        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        statusItem.menu = menu

        if UserDefaults.standard.bool(forKey: Self.keepAwakeKey) {
            start()   // renders on its way through
        } else {
            render()
        }
    }

    @objc private func toggle() {
        active ? stop() : start()
        // Persisted only here, on a deliberate click. start()/stop() are also
        // driven by caffeinate dying unexpectedly, and that should not be
        // recorded as the user choosing to switch the feature off.
        UserDefaults.standard.set(active, forKey: Self.keepAwakeKey)
    }

    private func start() {
        active = true
        // Prompts once if the permission has never been decided. Silent if the
        // user has already answered, so this is not a nag on every launch.
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        _ = AXIsProcessTrustedWithOptions(options as CFDictionary)

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

        // Without Accessibility the idle nudge silently does nothing while
        // caffeinate still holds the display, so the app looks like it is
        // working when half of it is not. Say so rather than just "On".
        let trusted = AXIsProcessTrusted()
        if active && !trusted {
            statusMenuItem.title = "Status: On — needs Accessibility"
        } else {
            statusMenuItem.title = active ? "Status: On" : "Status: Off"
        }
        accessibilityMenuItem?.isHidden = trusted
    }

    @objc private func openAccessibilitySettings() {
        let url = URL(string:
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
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
