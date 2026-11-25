# Compact — Design

## Intent

Compact is a free Mac menu bar app for a quick look at yourself through the camera before a call. It's
the user's own version of Hand Mirror, with every paid "Plus" feature free and a new vlog recorder added.
It's for the user and their friends. It won't be published on the App Store.

Background on how Hand Mirror does each feature: `docs/hand-mirror-study.md`. Compact is written from
scratch with Apple's frameworks; no Hand Mirror code, art, fonts, or name is reused.

## Goals

1. Click the menu bar icon → a popover drops down showing the live camera.
2. **Snaps:** take a photo (button or Space bar), shown on a Polaroid-style card with an optional date,
   draw on it with a marker, and save it as a PNG.
3. **Mic check:** a live level meter for the microphone, with a microphone picker.
4. **Floating window:** an alternative to the popover. It floats above other windows, can be dragged,
   has preset sizes, and stays open.
5. **Window shapes:** rounded rectangle, square corners, circle, capsule.
6. **Default position** for the floating window: four corners, center, or "remember where I left it".
7. **Menu bar icon picker:** a few icon choices.
8. **Notch trigger:** on Macs with a notch, clicking the notch opens Compact.
9. **Keyboard shortcut** to open and close Compact, plus **launch at login**.
10. **Vlog (new):** record camera + microphone to a `.mov` file saved locally. Recording keeps going if
    the popover closes. The menu bar icon turns into a red record dot while recording. There's a button
    that opens the saved-videos folder.

## Non-goals

- Reactions (they duplicate macOS's built-in video effects).
- In-app purchases, accounts, cloud anything.
- App Store publishing, iPhone or iPad versions.
- Saving to the Photos library (files go to folders instead).

## Anti-goals (it fails if…)

- The camera light stays on when Compact isn't visible and isn't recording.
- A recording is lost or corrupted because the popover closed or the app quit.
- It feels slow: the camera must appear within about a second of clicking.

## Constraints

- Built without Xcode: Swift 6.1 command-line tools, a Swift package, and a script that wraps the build
  into `Compact.app`. Tests use Swift Testing (`import Testing`), which was verified to work on this Mac.
- macOS 14.0 minimum. The user's Mac runs macOS 26.3 on Apple silicon.
- Ad-hoc code signing only. Friends must right-click → Open the first time. macOS may ask for camera
  permission again after each rebuild.
- Menu bar only: no Dock icon (`LSUIElement`).

## Approaches considered

1. **Native Swift, built with command-line tools (chosen).** Small, fast, real Mac app, and it can start
   today. It can move into Xcode later with the same code.
2. Native Swift in Xcode. Same code, but needs a 10+ GB download first. Deferred until publishing.
3. Electron or other web technology. Rejected: a heavy app (around 200 MB) that feels off in the menu bar.

## Decisions (Claude's calls, open to correction)

- **Name:** Compact (chosen by the user). Bundle ID `com.compact.app`.
- **Save locations:** snaps → `~/Pictures/Compact/`, vlogs → `~/Movies/Compact/`. Folders are created on
  first save.
- **File names:** `Compact Snap 2026-11-25 at 14.03.22.png`, `Compact Vlog 2026-11-25 at 14.03.22.mov`.
  A ` (2)`, ` (3)`… suffix is added if the name is taken.
- **Mirroring:** the preview is mirrored by default, like a real mirror (toggle in settings). Saved snaps
  and vlogs are **not** mirrored, so text reads correctly.
- **Marker font for snap captions:** "Marker Felt", which is built into macOS.
- **Floating window sizes:** small 240×180, medium 320×240, large 480×360. Circle and square shapes use
  the width as both sides.
- **Menu bar icons (SF Symbols):** `camera.fill` (default), `face.smiling`, `circle.inset.filled`,
  `sparkles`, `eye`. While recording: `record.circle.fill`, tinted red.
- **Mic meter:** dB from -60 to 0 maps linearly to 0–1. Anything below -60 is 0, anything above 0 is 1.
- **Keyboard shortcut library:** sindresorhus/KeyboardShortcuts (MIT), with no default shortcut set.
- **Camera lifecycle:** the camera runs only while the popover or floating window is visible, or while
  recording.

## Left to the builder

Exact visual styling of the controls bar, settings layout, marker colors (pick 4–5), and animation details.
