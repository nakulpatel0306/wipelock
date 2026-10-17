// WipeLock — locks your Mac's keyboard and trackpad so you can clean them.
//
// Unlock:        Cmd + Shift + U
// Safety net:    auto-unlocks after 10 minutes (change it by passing minutes, e.g. `./WipeLock 5`)
//
// Build & run (needs Xcode Command Line Tools: `xcode-select --install`):
//   swiftc WipeLock.swift -o WipeLock
//   ./WipeLock
//
// First run: macOS will ask you to give your terminal app Accessibility access
// (System Settings > Privacy & Security > Accessibility). Turn it on, then run again.

import Cocoa
import ApplicationServices

// MARK: - Settings

let minutes = Double(CommandLine.arguments.dropFirst().first ?? "") ?? 10
let unlockKeyCode: Int64 = 32 // the "U" key

// MARK: - State (globals so the C event-tap callback can reach them)

var tap: CFMachPort?
var blockedCount = 0
var secondsLeft = Int(minutes * 60)
var statusLabels: [NSTextField] = []
var finished = false

func updateStatus() {
    let m = secondsLeft / 60, s = secondsLeft % 60
    let text = "Blocked \(blockedCount) inputs  ·  auto unlock in \(m):\(String(format: "%02d", s))"
    statusLabels.forEach { $0.stringValue = text }
}

func finish() {
    guard !finished else { return }
    finished = true
    if let t = tap { CGEvent.tapEnable(tap: t, enable: false) }
    NSCursor.unhide()
    print("Unlocked. Blocked \(blockedCount) inputs.")
    NSApp.terminate(nil)
}

// MARK: - Permission check

let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
if !AXIsProcessTrustedWithOptions([promptKey: true] as CFDictionary) {
    print("""
    WipeLock needs Accessibility access to block input.
    Go to System Settings > Privacy & Security > Accessibility,
    turn on your terminal app (Terminal, iTerm, etc.), then run this again.
    """)
    exit(1)
}

// MARK: - Event tap (swallows every key, click, scroll, gesture)

let callback: CGEventTapCallBack = { _, type, event, _ in
    // macOS can switch a tap off if it thinks it's stuck; switch it right back on
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        if let t = tap { CGEvent.tapEnable(tap: t, enable: true) }
        return nil
    }

    if type == .keyDown {
        let code = event.getIntegerValueField(.keyboardEventKeycode)
        let flags = event.flags
        if code == unlockKeyCode && flags.contains(.maskCommand) && flags.contains(.maskShift) {
            DispatchQueue.main.async { finish() }
            return nil
        }
    }

    switch type {
    case .keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown, .scrollWheel:
        blockedCount += 1
        updateStatus()
    default:
        break
    }
    return nil // nil = event is dropped
}

// Key down/up, modifier changes, all mouse buttons, movement, drags,
// scroll, media/brightness keys (14) and trackpad gestures (29).
let eventTypes: [UInt64] = [1, 2, 3, 4, 5, 6, 7, 10, 11, 12, 14, 22, 25, 26, 27, 29]
let mask = eventTypes.reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << $1) }

tap = CGEvent.tapCreate(tap: .cghidEventTap, place: .headInsertEventTap,
                        options: .defaultTap, eventsOfInterest: mask,
                        callback: callback, userInfo: nil)
    ?? CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap,
                         options: .defaultTap, eventsOfInterest: mask,
                         callback: callback, userInfo: nil)

guard let eventTap = tap else {
    print("Couldn't start the input block. Double check Accessibility access and try again.")
    exit(1)
}

let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
CGEvent.tapEnable(tap: eventTap, enable: true)

// MARK: - Fullscreen cover on every display

let app = NSApplication.shared
app.setActivationPolicy(.regular)

let bg = NSColor(calibratedRed: 0.055, green: 0.078, blue: 0.086, alpha: 1)
let accent = NSColor(calibratedRed: 0.50, green: 0.84, blue: 0.78, alpha: 1)
let muted = NSColor(calibratedRed: 0.55, green: 0.63, blue: 0.65, alpha: 1)

var windows: [NSWindow] = []

func makeLabel(_ text: String, size: CGFloat, weight: NSFont.Weight, color: NSColor, mono: Bool = false) -> NSTextField {
    let l = NSTextField(labelWithString: text)
    l.font = mono ? .monospacedSystemFont(ofSize: size, weight: weight) : .systemFont(ofSize: size, weight: weight)
    l.textColor = color
    l.alignment = .center
    return l
}

for screen in NSScreen.screens {
    let w = NSWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false, screen: screen)
    w.level = .screenSaver
    w.backgroundColor = bg
    w.isOpaque = true
    w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
    w.setFrame(screen.frame, display: true)

    let title = makeLabel("Wipe away.", size: 72, weight: .bold, color: .white)
    let hint = makeLabel("Keyboard and trackpad are locked.  Press  ⌘ ⇧ U  to unlock.", size: 22, weight: .medium, color: accent)
    let status = makeLabel("", size: 14, weight: .regular, color: muted, mono: true)
    statusLabels.append(status)

    let stack = NSStackView(views: [title, hint, status])
    stack.orientation = .vertical
    stack.alignment = .centerX
    stack.spacing = 18
    stack.translatesAutoresizingMaskIntoConstraints = false

    let content = NSView(frame: screen.frame)
    content.addSubview(stack)
    NSLayoutConstraint.activate([
        stack.centerXAnchor.constraint(equalTo: content.centerXAnchor),
        stack.centerYAnchor.constraint(equalTo: content.centerYAnchor),
    ])
    w.contentView = content
    w.makeKeyAndOrderFront(nil)
    windows.append(w)
}

updateStatus()
app.activate(ignoringOtherApps: true)
app.presentationOptions = [.hideDock, .hideMenuBar, .disableProcessSwitching,
                           .disableForceQuit, .disableSessionTermination,
                           .disableHideApplication, .disableAppleMenu]
NSCursor.hide()

// MARK: - Safety-net countdown

Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
    secondsLeft -= 1
    updateStatus()
    if secondsLeft <= 0 { finish() }
}

print("Locked. Press Cmd + Shift + U to unlock (auto unlock in \(Int(minutes)) min).")
app.run()
