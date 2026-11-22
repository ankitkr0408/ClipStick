# ClipStick Support & Troubleshooting Guide 🛠️

A complete reference guide covering every common scenario for both **non-technical users** and **developers**.

---

## 🧭 Quick Links

- [Scenario 1: macOS Security Warning ("Cannot verify developer")](#scenario-1-macos-security-warning-cannot-verify-developer)
- [Scenario 2: "Where is the app? I can't find a window open!"](#scenario-2-where-is-the-app-i-cant-find-a-window-open)
- [Scenario 3: "No developer tools found" / Xcode Compilation Error](#scenario-3-no-developer-tools-found--xcode-compilation-error)
- [Scenario 4: Screenshots are not auto-importing](#scenario-4-screenshots-are-not-auto-importing)
- [Scenario 5: Apple Silicon (M1/M2/M3/M4) vs Intel Macs](#scenario-5-apple-silicon-m1m2m3m4-vs-intel-macs)
- [Scenario 6: Launch Automatically on Mac Startup](#scenario-6-launch-automatically-on-mac-startup)
- [Scenario 7: How to Clear Data or Completely Uninstall](#scenario-7-how-to-clear-data-or-completely-uninstall)

---

### Scenario 1: macOS Security Warning ("Cannot verify developer")

#### Why this happens:
ClipStick is a 100% free and open-source project. Apple displays a security prompt for open-source apps that are distributed outside the Mac App Store without a paid enterprise certificate.

#### Non-Tech Solution (Mouse only — No Terminal):
1. Go to your **Applications** folder in Finder.
2. **Right-Click** (or hold `Control` and click) on **`ClipStick.app`**.
3. Click **Open** from the menu.
4. A dialog will appear asking if you want to open it. Click **Open**!
5. *You only have to do this once. After this, it will open normally.*

> **Alternative via System Settings**: Go to **System Settings** → **Privacy & Security** → scroll down to the "Security" section → click **"Open Anyway"** next to ClipStick.

#### Power User / Terminal Solution:
```bash
xattr -cr /Applications/ClipStick.app
```

---

### Scenario 2: "Where is the app? I can't find a window open!"

#### Explanation:
ClipStick is designed as a **lightweight menu bar utility** (like Spotlight or Raycast). It doesn't clutter your Dock with a permanent window.

#### How to use it:
1. **Shortcut**: Press **`Option + Space`** (`⌥ Space`) anywhere on your Mac to toggle the floating clipboard HUD.
2. **Menu Bar**: Look at the top-right menu bar near your Wi-Fi and Battery icons for the **clipboard icon**. Click it to access settings, toggle OCR, or view history.

---

### Scenario 3: "No developer tools found" / Xcode Compilation Error

#### Error message in Terminal:
```
xcode-select: note: No developer tools were found, requesting install.
No usable macOS SDK found
```

#### Why this happens:
This occurs when a non-developer Mac user attempts to compile Swift source code without having Apple's Xcode Developer Tools installed.

#### Solution:
**You do not need to install Xcode!** Use our pre-built binary:
1. Download the pre-compiled app directly:  
   👉 **[Download ClipStick.zip (Pre-built)](https://raw.githubusercontent.com/ankitkr0408/ClipStick/main/downloads/ClipStick.zip)**
2. Unzip it and drag **`ClipStick.app`** to your **Applications** folder.

---

### Scenario 4: Screenshots are not auto-importing

#### How to check:
1. Click the ClipStick icon in your top menu bar.
2. Ensure **"Import Screenshots from Folder"** has a checkmark (`✓`).
3. If macOS displays a permission pop-up asking for access to your *Desktop* or *Documents* folder, click **Allow**.

> ClipStick checks the default macOS screenshot location (`~/Desktop` or custom save folder) and automatically captures newly saved screenshots in real time.

---

### Scenario 5: Apple Silicon (M1/M2/M3/M4) vs Intel Macs

#### Native Universal Binary:
ClipStick is compiled as a **Universal Mach-O 64-bit Binary** supporting both:
- **`arm64`**: Apple Silicon (M1, M2, M3, M4, Pro, Max, Ultra)
- **`x86_64`**: Intel-based Macs

It runs at native speed on both architectures with zero emulation required.

---

### Scenario 6: Launch Automatically on Mac Startup

1. Click the ClipStick icon in your top menu bar.
2. Click **"Launch at Login"** so a checkmark (`✓`) appears.
3. ClipStick will now quietly start in the background every time you turn on or restart your Mac.

---

### Scenario 7: How to Clear Data or Completely Uninstall

#### Clear History & Data:
- Click the ClipStick menu bar icon → **Clear History…**
- Or click **Open Data Folder** to view local files (`~/Library/Application Support/ClipStick/`).

#### Uninstall:
1. Quit ClipStick: Click the menu bar icon → **Quit ClipStick** (`Cmd + Q`).
2. Drag `ClipStick.app` from your `/Applications` folder to the **Trash**.
3. *(Optional)* Delete user data folder:
   ```bash
   rm -rf ~/Library/Application\ Support/ClipStick
   ```

---

## Need More Help?

If you encounter any edge cases or bugs:
- Open an issue on GitHub: **[github.com/ankitkr0408/ClipStick/issues](https://github.com/ankitkr0408/ClipStick/issues)**
- Contributions, feedback, and pull requests are warmly welcomed!
