# MacAutoClicker (SwiftUI, macOS)

A SwiftUI macOS app that simulates mouse clicks with:
- Delayed start or start after first physical click
- Adjustable interval between clicks
- Finite or infinite count
- Global hotkeys (Start: ⌘⌥S, Stop: ⌘⌥X)

It requires Accessibility permissions to control the mouse and listen to global hotkeys.

## Project Setup (Xcode)
1. Open Xcode → File → New → Project… → macOS → App.
2. Name: `MacAutoClicker`, Interface: SwiftUI, Language: Swift.
3. After creation, replace the generated files with these:
   - Replace the `App` and `ContentView` with the ones in `Swift/MacAutoClicker/`.
   - Add the other Swift files from `Swift/MacAutoClicker/` to your Xcode target.
4. In Signing & Capabilities, ensure a development team is selected so you can run locally.
5. Build & Run.
6. On first launch, macOS will prompt for Accessibility permissions — approve it.
   - System Settings → Privacy & Security → Accessibility → enable your app.

## Usage
- Configure interval, count, start mode, and button.
- Click Start/Stop or use hotkeys:
  - Start: ⌘⌥S
  - Stop:  ⌘⌥X
- "After First Click" mode arms and then starts on your next physical click.

## Notes
- Intervals below a few milliseconds may be limited by system timing.
- If clicks/hotkeys don’t fire, re-check Accessibility settings.
- Global hotkeys use Carbon `RegisterEventHotKey` (works even when the app is not focused).