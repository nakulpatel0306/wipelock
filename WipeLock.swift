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

let usage = """
Usage: WipeLock [minutes]

Locks the keyboard and trackpad until you press Cmd + Shift + U.
Unlocks on its own after 10 minutes, or after [minutes] if you pass a number.
"""

let arguments = Array(CommandLine.arguments.dropFirst())
if arguments.contains("-h") || arguments.contains("--help") {
    print(usage)
    exit(0)
}

let minutes: Double
if let arg = arguments.first {
    guard let value = Double(arg), value > 0 else {
        print("\"\(arg)\" isn't a number of minutes. Try something like `WipeLock 5`.\n\n\(usage)")
        exit(1)
    }
    minutes = value
} else {
    minutes = 10
}

let unlockKeyCode: Int64 = 32 // the "U" key
let totalSeconds = max(1, Int((minutes * 60).rounded()))
let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion

// MARK: - Theme (Kanagawa Dragon)

extension NSColor {
    convenience init(hex: UInt32) {
        self.init(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
                  green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255,
                  alpha: 1)
    }
}

enum Palette {
    static let background = NSColor(hex: 0x181616)
    static let surface = NSColor(hex: 0x282727)
    static let border = NSColor(hex: 0x393836)
    static let text = NSColor(hex: 0xC5C9C5)
    static let secondary = NSColor(hex: 0xC5C9C5).withAlphaComponent(0.6)
    static let accent = NSColor(hex: 0x8EA4A2)
}

func roundedFont(_ size: CGFloat, _ weight: NSFont.Weight, fixedDigits: Bool = false) -> NSFont {
    let base = fixedDigits ? NSFont.monospacedDigitSystemFont(ofSize: size, weight: weight)
                           : NSFont.systemFont(ofSize: size, weight: weight)
    guard let descriptor = base.fontDescriptor.withDesign(.rounded) else { return base }
    return NSFont(descriptor: descriptor, size: size) ?? base
}

func makeLabel(_ text: String, font: NSFont, color: NSColor) -> NSTextField {
    let label = NSTextField(labelWithString: text)
    label.font = font
    label.textColor = color
    label.translatesAutoresizingMaskIntoConstraints = false
    return label
}

func formatTime(_ seconds: Int) -> String {
    String(format: "%d:%02d", seconds / 60, seconds % 60)
}

// MARK: - Views

final class Keycap: NSView {
    private let label: NSTextField

    var isLit = false { didSet { applyStyle() } }

    private func applyStyle() {
        layer?.borderColor = (isLit ? Palette.accent : Palette.border).cgColor
        layer?.backgroundColor = (isLit ? Palette.accent.withAlphaComponent(0.18) : Palette.surface).cgColor
        label.textColor = isLit ? Palette.accent : Palette.text
    }

    init(_ symbol: String) {
        label = makeLabel(symbol, font: roundedFont(18, .semibold), color: Palette.text)
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 9
        layer?.borderWidth = 1
        translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 42),
            heightAnchor.constraint(equalToConstant: 42),
            label.centerXAnchor.constraint(equalTo: centerXAnchor),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        // didSet doesn't run during init, so set the resting look directly
        applyStyle()
    }

    required init?(coder: NSCoder) { fatalError() }
}

final class ProgressBar: NSView {
    private let fill = CALayer()

    var fraction: CGFloat = 1 { didSet { needsLayout = true } }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = Palette.border.cgColor
        layer?.cornerRadius = 2
        fill.backgroundColor = Palette.accent.cgColor
        fill.cornerRadius = 2
        fill.anchorPoint = .zero
        layer?.addSublayer(fill)
        translatesAutoresizingMaskIntoConstraints = false
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        // Each tick lasts a second, so a one-second linear slide makes the bar drain smoothly
        CATransaction.begin()
        CATransaction.setAnimationDuration(reduceMotion ? 0 : 1)
        CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .linear))
        fill.frame = CGRect(x: 0, y: 0, width: bounds.width * fraction, height: bounds.height)
        CATransaction.commit()
    }
}

final class CoverView: NSView {
    private let badge = NSView()
    private let title = makeLabel("Wipe Away", font: roundedFont(64, .bold), color: Palette.text)
    private let subtitle = makeLabel("Your keyboard and trackpad are locked, so clean as much as you like.",
                                     font: roundedFont(20, .regular), color: Palette.secondary)
    private let command = Keycap("⌘")
    private let shift = Keycap("⇧")
    private let letter = Keycap("U")
    private let countdown = makeLabel("", font: roundedFont(15, .medium, fixedDigits: true), color: Palette.secondary)
    private let blocked = makeLabel("", font: roundedFont(15, .medium, fixedDigits: true), color: Palette.secondary)
    private let progress = ProgressBar()
    private var lastRipple = Date.distantPast

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = Palette.background.cgColor

        badge.wantsLayer = true
        badge.layer?.backgroundColor = Palette.surface.cgColor
        badge.layer?.borderColor = Palette.border.cgColor
        badge.layer?.borderWidth = 1
        badge.layer?.cornerRadius = 56
        badge.translatesAutoresizingMaskIntoConstraints = false

        let sparkle = NSImageView()
        sparkle.image = NSImage(systemSymbolName: "sparkles", accessibilityDescription: "Cleaning")?
            .withSymbolConfiguration(.init(pointSize: 44, weight: .regular))
        sparkle.contentTintColor = Palette.accent
        sparkle.translatesAutoresizingMaskIntoConstraints = false
        badge.addSubview(sparkle)

        let press = makeLabel("Press", font: roundedFont(17, .medium), color: Palette.secondary)
        let toUnlock = makeLabel("to unlock", font: roundedFont(17, .medium), color: Palette.secondary)
        let hint = NSStackView(views: [press, command, shift, letter, toUnlock])
        hint.spacing = 8
        hint.setCustomSpacing(14, after: press)
        hint.setCustomSpacing(14, after: letter)

        let stack = NSStackView(views: [badge, title, subtitle, hint])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.setCustomSpacing(36, after: badge)
        stack.setCustomSpacing(12, after: title)
        stack.setCustomSpacing(44, after: subtitle)
        stack.translatesAutoresizingMaskIntoConstraints = false

        [stack, countdown, blocked, progress].forEach(addSubview)
        NSLayoutConstraint.activate([
            badge.widthAnchor.constraint(equalToConstant: 112),
            badge.heightAnchor.constraint(equalToConstant: 112),
            sparkle.centerXAnchor.constraint(equalTo: badge.centerXAnchor),
            sparkle.centerYAnchor.constraint(equalTo: badge.centerYAnchor),

            stack.centerXAnchor.constraint(equalTo: centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor, constant: -20),

            progress.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 56),
            progress.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -56),
            progress.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -48),
            progress.heightAnchor.constraint(equalToConstant: 4),

            countdown.leadingAnchor.constraint(equalTo: progress.leadingAnchor),
            countdown.bottomAnchor.constraint(equalTo: progress.topAnchor, constant: -14),
            blocked.trailingAnchor.constraint(equalTo: progress.trailingAnchor),
            blocked.bottomAnchor.constraint(equalTo: progress.topAnchor, constant: -14),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    func update(secondsLeft: Int, blockedCount: Int) {
        countdown.stringValue = "Unlocks on its own in \(formatTime(secondsLeft))"
        switch blockedCount {
        case 0: blocked.stringValue = "Nothing blocked yet"
        case 1: blocked.stringValue = "1 input blocked"
        default: blocked.stringValue = "\(blockedCount) inputs blocked"
        }
        progress.fraction = CGFloat(secondsLeft) / CGFloat(totalSeconds)
    }

    func showModifiers(_ flags: CGEventFlags) {
        command.isLit = flags.contains(.maskCommand)
        shift.isLit = flags.contains(.maskShift)
    }

    func showUnlocking() {
        letter.isLit = true
        title.stringValue = "All Clean"
    }

    // A ring spreads out from the badge each time an input is caught
    func ripple() {
        guard !reduceMotion, let root = layer, Date().timeIntervalSince(lastRipple) > 0.12 else { return }
        lastRipple = Date()

        let ring = CAShapeLayer()
        ring.frame = badge.convert(badge.bounds, to: self)
        ring.path = CGPath(ellipseIn: badge.bounds, transform: nil)
        ring.fillColor = nil
        ring.strokeColor = Palette.accent.cgColor
        ring.lineWidth = 1.5
        root.insertSublayer(ring, at: 0)

        CATransaction.begin()
        CATransaction.setCompletionBlock { ring.removeFromSuperlayer() }
        let grow = CABasicAnimation(keyPath: "transform.scale")
        grow.fromValue = 1
        grow.toValue = 2.6
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 0.6
        fade.toValue = 0
        let group = CAAnimationGroup()
        group.animations = [grow, fade]
        group.duration = 1.1
        group.timingFunction = CAMediaTimingFunction(name: .easeOut)
        ring.opacity = 0
        ring.add(group, forKey: "ripple")
        CATransaction.commit()
    }

    // One soft band sweeps across the screen as the lock goes on, like a cloth
    func sweep() {
        guard !reduceMotion, let root = layer else { return }
        let width = bounds.width * 0.45
        let band = CAGradientLayer()
        band.colors = [NSColor.clear, Palette.accent.withAlphaComponent(0.09), NSColor.clear].map(\.cgColor)
        band.startPoint = CGPoint(x: 0, y: 0.5)
        band.endPoint = CGPoint(x: 1, y: 0.5)
        band.frame = CGRect(x: -width, y: 0, width: width, height: bounds.height)
        root.addSublayer(band)

        CATransaction.begin()
        CATransaction.setCompletionBlock { band.removeFromSuperlayer() }
        let move = CABasicAnimation(keyPath: "position.x")
        move.fromValue = -width / 2
        move.toValue = bounds.width + width / 2
        move.duration = 1.3
        move.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        band.position.x = bounds.width + width / 2
        band.add(move, forKey: "sweep")
        CATransaction.commit()
    }
}

final class CoverWindow: NSWindow {
    override var canBecomeKey: Bool { true }
}

// MARK: - State (globals so the C event-tap callback can reach them)

var tap: CFMachPort?
var blockedCount = 0
var secondsLeft = totalSeconds
var windows: [CoverWindow] = []
var covers: [CoverView] = []
var finished = false

func refresh() {
    covers.forEach { $0.update(secondsLeft: secondsLeft, blockedCount: blockedCount) }
}

func finish(timedOut: Bool) {
    guard !finished else { return }
    finished = true
    if let t = tap { CGEvent.tapEnable(tap: t, enable: false) }
    covers.forEach { $0.showUnlocking() }

    NSAnimationContext.runAnimationGroup({ context in
        context.duration = reduceMotion ? 0 : 0.45
        windows.forEach { $0.animator().alphaValue = 0 }
    }, completionHandler: {
        NSCursor.unhide()
        let elapsed = formatTime(totalSeconds - secondsLeft)
        let inputs = blockedCount == 1 ? "1 input" : "\(blockedCount) inputs"
        print(timedOut ? "Time's up. Unlocked after \(elapsed) with \(inputs) blocked."
                       : "Unlocked after \(elapsed) with \(inputs) blocked.")
        NSApp.terminate(nil)
    })
}

// MARK: - Permission check

let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
if !AXIsProcessTrustedWithOptions([promptKey: true] as CFDictionary) {
    print("""
    WipeLock needs Accessibility access to block input.
    Go to System Settings > Privacy & Security > Accessibility,
    turn on your terminal app (Terminal, Ghostty, iTerm, etc.), then run this again.
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

    var counts = false
    switch type {
    case .flagsChanged:
        covers.forEach { $0.showModifiers(event.flags) }
    case .keyDown:
        let code = event.getIntegerValueField(.keyboardEventKeycode)
        if code == unlockKeyCode && event.flags.contains(.maskCommand) && event.flags.contains(.maskShift) {
            DispatchQueue.main.async { finish(timedOut: false) }
            return nil
        }
        // Holding a key down repeats it; count the press once
        counts = event.getIntegerValueField(.keyboardEventAutorepeat) == 0
    case .leftMouseDown, .rightMouseDown, .otherMouseDown:
        counts = true
    case .scrollWheel:
        // One swipe sends dozens of scroll events; only the first one counts
        counts = event.getIntegerValueField(.scrollWheelEventScrollPhase) == 1
    default:
        break
    }

    if counts {
        blockedCount += 1
        refresh()
        covers.forEach { $0.ripple() }
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

for screen in NSScreen.screens {
    let window = CoverWindow(contentRect: screen.frame, styleMask: .borderless,
                             backing: .buffered, defer: false, screen: screen)
    window.level = .screenSaver
    window.backgroundColor = Palette.background
    window.isOpaque = true
    window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
    window.setFrame(screen.frame, display: true)

    let cover = CoverView(frame: NSRect(origin: .zero, size: screen.frame.size))
    window.contentView = cover
    window.alphaValue = 0
    window.makeKeyAndOrderFront(nil)
    windows.append(window)
    covers.append(cover)
}

refresh()
app.activate(ignoringOtherApps: true)
app.presentationOptions = [.hideDock, .hideMenuBar, .disableProcessSwitching,
                           .disableForceQuit, .disableSessionTermination,
                           .disableHideApplication, .disableAppleMenu]
NSCursor.hide()

NSAnimationContext.runAnimationGroup { context in
    context.duration = reduceMotion ? 0 : 0.35
    windows.forEach { $0.animator().alphaValue = 1 }
}
covers.forEach { $0.layoutSubtreeIfNeeded(); $0.sweep() }

// MARK: - Safety-net countdown

Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
    secondsLeft -= 1
    refresh()
    if secondsLeft <= 0 { finish(timedOut: true) }
}

print("Locked. Press Cmd + Shift + U to unlock, or wait \(formatTime(totalSeconds)) for it to unlock on its own.")
app.run()
