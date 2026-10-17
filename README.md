# WipeLock - A Mac Cleaning Lock

A small macOS utility that locks the keyboard and trackpad so you can wipe them down. A fullscreen cover goes up on every display, every key press, click and gesture is swallowed, and one shortcut brings it all back.

## At a Glance

- **Stack:** Swift, AppKit, Core Graphics event taps (no external libraries)
- **Platforms:** macOS
- **State:** Complete

## Features

- Blocks keys, clicks, scrolling, trackpad gestures and media keys
- Fullscreen cover on every connected display
- Unlock with Cmd + Shift + U
- Auto unlocks after 10 minutes, or any number of minutes you pass in
- Live count of blocked inputs and time left

## Project Structure

```
.
└── WipeLock.swift   # Permission check, event tap, fullscreen cover and countdown
```

## Running Locally

Needs the Xcode Command Line Tools (`xcode-select --install`).

1. Clone the repo:
   ```bash
   git clone https://github.com/nakulpatel0306/wipelock.git
   cd wipelock
   ```
2. Compile and run:
   ```bash
   swiftc WipeLock.swift -o WipeLock
   ./WipeLock
   ```
   Pass a number to change the auto unlock time, e.g. `./WipeLock 5` for 5 minutes.

On the first run macOS asks for Accessibility access. Turn on your terminal app in System Settings > Privacy & Security > Accessibility, then run it again.

## How to Use

- Run it, wait for the cover to appear, then clean
- Press Cmd + Shift + U to unlock
- If you forget the shortcut, it unlocks itself when the timer runs out
