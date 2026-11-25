# How Hand Mirror is built (study notes)

Studied from the copy installed at /Applications/Hand Mirror.app (version 4.0.6) using REA and Apple's
command-line tools. What we could see: the Apple frameworks it links, the Apple classes it calls, and
the names and messages left in the app. No decompiled code was read (no decompiler is installed), so
anything marked *guess* is an informed inference, not something observed.

We use this to learn the approach. Our app's code is written from scratch.

## The big picture

- Written in **Swift**, with screens drawn in **SwiftUI** and Mac plumbing in **AppKit**.
- Needs three permissions, declared in its Info.plist: **camera**, **microphone** (for the level meter),
  and **Photos** (to save snaps).
- Requires macOS 14.4 or later.

## Feature by feature

| Feature | How it works, in plain English | Apple tools seen |
|---|---|---|
| Menu bar icon + dropdown | Puts an icon in the menu bar. Clicking it opens a popover, a little bubble window attached to the icon. The camera screen inside is SwiftUI. | `NSStatusBar`, `NSPopover`, `CameraHostingViewController` → `CameraView` |
| Live camera | Opens a "capture session" that connects the camera to a preview layer, which paints live video onto the screen. You can pick a camera, zoom, and mirror the image. | `AVCaptureSession`, `AVCaptureDeviceInput`, `AVCaptureVideoPreviewLayer`, `AVCaptureDeviceDiscoverySession`; settings `zoomLevel`, `photoIsMirrored` |
| Snaps | Grabs one frame from the camera feed. Places it on a Polaroid-style card drawn in SwiftUI (a handwriting font ships in the app, and the date is optional). Turns the card into an image and saves it to Photos, in its own album, or to a folder you choose. | `AVCaptureVideoDataOutput`, `CIImage`/`CIContext`, SwiftUI `ImageRenderer`, `SnapCardView`, `HandWritingFont.ttf`, `PHPhotoLibrary`, `PHAssetCollectionChangeRequest`, `NSSavePanel` |
| Marker drawing on snaps | A "Sharpie" drawing layer over the snap, with a choice of colors and a custom marker cursor. | `SharpieView`, `SharpieColorColumn`, `NSCursor` |
| Mic check | Listens to the microphone (without recording) and reads the volume level about many times per second. A bar meter moves with it. You can pick the microphone. | `AVCaptureAudioDataOutput`, `AVCaptureAudioChannel.averagePowerLevel`, `AudioMeterView` |
| Smart Window | Instead of the popover, the camera opens in a normal floating window. It has preset sizes, an optional locked shape, and stays above other windows. | `SmartWindow` (an `NSPanel`/`NSWindow`), `setLevel`, `lockAspectRatio`, `smartWindowAvailableSizes` |
| Window masks | Cuts the camera view into a shape, such as a circle or rounded corners, by clipping it with a SwiftUI shape. *Guess:* the full list of shapes; only "circle" and a corner-radius setting are visible. | `AnyShape`, `windowMaskOptions`, `windowMaskCornerRadius` |
| Default position | Preset spots on screen, or "remember where I dragged it". | `windowPositions`, `manualWindowPosition` |
| Custom icons | A small picker that swaps the menu bar icon, and the app icon too. | `AppIconManager`, `AppIconView` |
| Notch trigger | Places an invisible window over the camera notch. Clicking it opens the camera. It also checks whether the menu bar icon is hidden behind the notch, using Accessibility, and warns you if so. *Guess:* the notch area comes from the screen's "safe area" values. | `NotchTrigger`, `NotchView`, `NSScreen`, `AXUIElementCopyElementAtPosition` |
| Keyboard shortcut | Uses **KeyboardShortcuts**, a free open-source library by Sindre Sorhus (MIT license). We can use the same library. | `KeyboardShortcuts` bundle |
| Launch at login | Apple's standard "open at login" switch. | `SMAppService` |
| Reactions | Calls macOS's built-in video reactions (balloons, hearts, and so on) on supported Macs. | `AVCaptureDevice.performEffect(for:)` |
| Plus purchase | In-app purchase through Apple. **We don't need this at all.** | `StoreKit` |
| Video recording | **Doesn't exist.** No video-recording classes appear anywhere. This is new in our app. | none |

## What this means for our app

- Everything above uses only Apple's own frameworks plus one free library. Nothing needs to be copied.
- **Vlog (new):** add `AVCaptureMovieFileOutput` to the same capture session, with the camera and
  microphone as inputs. It writes a `.mov` file straight to a folder in Movies. This is about 50 lines
  on top of the camera code we'd already have.
- Rough build order: menu bar + popover + live camera → mic check → snaps → floating window + shapes +
  position → vlog → icons, shortcut, login → notch trigger (the trickiest, so last).
