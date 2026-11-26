# Compact

Compact is a tiny camera mirror that lives in your Mac's menu bar. Click it before a call to check how you look, test your microphone, snap a photo, or record a quick vlog. The camera is only on while Compact is open.

Made for macOS 14 (Sonoma) or newer.

## Install (for friends)

Open the **Terminal** app, paste this, and press Return:

```
curl -fsSL https://github.com/trishabthakkar/compact/releases/latest/download/install.sh | sh
```

That's it: Compact installs into Applications and opens. Look for the lipstick in your menu bar (top right), and click **Allow** when your Mac asks for the camera and microphone. Run the same line again any time to update.

### Installing from the zip instead

1. Download `Compact.zip` from the [latest release](https://github.com/trishabthakkar/compact/releases/latest) and unzip it.
2. Open the **Compact** folder and drag **`Compact.app`** into your **Applications** folder.
3. Open Compact once. macOS will say it can't verify the app, because it isn't from the App Store. Click **Done**.
4. Open **System Settings → Privacy & Security**, scroll down to the message about Compact, and click **Open Anyway**.
   (On macOS 14 you can instead right-click Compact, choose **Open**, then click **Open**.)
5. If macOS says the app is "damaged", paste this into Terminal, then open Compact again:

   ```
   xattr -dr com.apple.quarantine /Applications/Compact.app
   ```

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

## Publishing a new version

Commit your changes, then run (needs the GitHub CLI: `brew install gh && gh auth login`):

```
scripts/release.sh 1.1
```

This builds the app, creates a GitHub Release with `Compact.zip` and `install.sh`, and the install line above starts serving the new version.

