# Compact

Compact is a tiny camera mirror that lives in your Mac's menu bar. Click it before a call to check how you look, test your microphone, snap a photo, or record a quick vlog. The camera is only on while Compact is open.

Made for macOS 14 (Sonoma) or newer.

## Install (for friends)

1. Unzip `Compact.zip`.
2. Open the **Compact** folder and drag **`Compact.app`** (the app with the mirror icon) into your **Applications** folder.
3. Open Compact once. macOS will say it can't verify the app, because it isn't from the App Store. Click **Done**.
4. Open **System Settings → Privacy & Security**, scroll down to the message about Compact, and click **Open Anyway**. Enter your Mac password if asked, then click **Open Anyway** once more.
   (On macOS 14 and older you can instead right-click Compact, choose **Open**, then click **Open**. macOS 15 and newer removed that shortcut.)
5. Allow **camera** and **microphone** access when your Mac asks.

Compact appears as an icon in the menu bar at the top of the screen. Click it to see yourself.

### If "Open Anyway" doesn't appear, or macOS says the app is "damaged"

It isn't. macOS is just being cautious about apps from outside the App Store. Open the Terminal app, paste this, and press Return:

```
xattr -cr /Applications/Compact.app
```

Then open Compact again.

## What it does

- Live camera preview from the menu bar (popover or floating window)
- Mic check meter
- Snaps, saved to `Pictures/Compact`
- Vlog recording, saved to `Movies/Compact`
- Optional keyboard shortcut and launch at login (see Settings)
- On MacBooks with a notch, you can turn on "click the notch to open Compact"

## Build it yourself

You need the Swift command line tools (no Xcode required).

```
swift test              # run the tests
scripts/build-app.sh    # makes build/Compact.app
scripts/package-zip.sh  # makes build/Compact.zip to share
```
