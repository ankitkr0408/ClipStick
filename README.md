# ClipStick

A lightweight, native macOS clipboard manager built in Swift and SwiftUI, designed for developer workflows, visual debugging, and AI bug analysis.

[![macOS](https://img.shields.io/badge/platform-macOS%2014%2B-blue.svg)](https://apple.com/macos)
[![Swift](https://img.shields.io/badge/swift-5.9%2B-orange.svg)](https://swift.org)
[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

---

<p align="center">
  <img src="assets/clipboard-grid.jpg" alt="ClipStick Floating HUD" width="850">
</p>

---

## Why ClipStick?

When debugging code or reproducing UI issues, developers often take multiple screenshots in rapid succession alongside copying logs and error traces. Default clipboards only keep the latest item.

**ClipStick** runs silently in the background, automatically tracks all captures locally, and lets you batch-select multiple screenshots to merge or export directly into AI prompts (Claude, ChatGPT) or GitHub issues.

---

## Visual Tour

### Multi-Item Selection & 1-Click Stitching
Select multiple screenshots with numbered click-order badges, and merge them into a single clean collage ready for bug reports or LLMs:

<p align="center">
  <img src="assets/batch-stitch.jpg" alt="Batch Selection and Stitching" width="850">
</p>

### Native macOS Menu Bar Controls
Access history, toggle folder screenshot watchers, pause capture, or configure background text recognition (OCR) with one click:

<p align="center">
  <img src="assets/menu-bar.jpg" alt="Menu Bar Controls" width="450">
</p>

---

## Key Features

- **Automatic Background Capture**: Intercepts screenshots and copied text without stealing window focus.
- **Multi-Select & Stitching**: Select 2 or more screenshots with checkboxes and merge them vertically or horizontally into one image.
- **Built-in Redact & Crop**:
  - **Redact**: Blackout sensitive API keys, passwords, or personal data before sharing.
  - **Crop**: Fast 8-handle crop box with rule-of-thirds grid.
  - **Annotations**: Highlight lines of code with markers, add arrows, boxes, and step counters.
- **Copy for AI / Markdown Bundle**: Formats selected logs and screenshots into structured Markdown context ready for LLMs.
- **Native Vision OCR**: Extracts text and code snippets from captured images in the background.
- **100% Local & Private**: All data is stored in local SQLite and disk storage. Zero cloud sync, zero telemetry.
- **Fluid & Resizable HUD**: Summon the floating panel anytime via hotkey (`Option + Space`), resize from the edges or bottom-right corner, and reposition via the drag handle.

---

## 🔒 Privacy & Data Safety: 100% Local, Zero Cloud

Your clipboard contains your most sensitive data — passwords, credentials, personal chats, and private source code. 

**ClipStick is designed with privacy-first architecture:**

- **Zero Cloud Sync**: Nothing is ever uploaded to the cloud or external servers. Your clips never leave your Mac.
- **Zero Telemetry or Analytics**: There are no tracking scripts, analytics SDKs, or background telemetry pings.
- **Stored Exclusively on Your Machine**: Metadata and history live inside a local SQLite database on your Mac (`~/Library/Application Support/`), and images are cached locally on your disk.
- **Works 100% Offline**: Turn off Wi-Fi completely — every feature (capture, search, markup, crop, OCR, and stitching) functions with zero internet access.
- **Fully Open-Source & Auditable**: You don't have to take our word for it — the complete source code is public and transparent right here. Feel free to inspect the network calls (or lack thereof!).

---

## Requirements

- macOS 14.0 (Sonoma) or later
- Apple Silicon or Intel Mac

---

## 🚀 Installation Guide

### Option 1: Direct Download (Pre-built App — 370 KB, Zero Terminal ⭐️)

1. **[Click here to download `ClipStick.zip`](https://raw.githubusercontent.com/ankitkr0408/ClipStick/main/downloads/ClipStick.zip)**.
2. Double-click the downloaded `ClipStick.zip` file to extract `ClipStick.app`.
3. Drag **`ClipStick.app`** into your **`Applications`** folder and open it!

> **Note on first launch:** Since ClipStick is an independent open-source project, macOS Gatekeeper may show a prompt. Simply **Right-Click (or Control-Click) `ClipStick.app` → Open → Click "Open"**.

---

### Option 2: 1-Click Terminal Install (No Xcode needed)

Open **Terminal** on your Mac (`Cmd + Space` → type `Terminal` → press Enter), paste this line, and hit **Enter**:

```bash
curl -fsSL https://raw.githubusercontent.com/ankitkr0408/ClipStick/main/scripts/install.sh | bash
```

*Works on all Macs automatically, even without developer tools or Xcode!*

---

### Option 3: If you downloaded the repo ZIP (`ClipStick-main.zip`)

If you clicked GitHub's green **`<> Code` → "Download ZIP"** button:

1. Open the extracted **`ClipStick-main`** folder in Finder.
2. Simply **Double-Click on `Install.command`**!
3. Done! It automatically extracts the pre-built app into your `/Applications` folder without compiling.

---

### Option 4: Clone & Build (For Developers)

```bash
git clone https://github.com/ankitkr0408/ClipStick.git
cd ClipStick
./scripts/install.sh
```

---

## Keyboard Shortcuts

| Shortcut | Action |
|---|---|
| `Option + Space` | Toggle ClipStick overlay |
| `Return` | Copy selected item to clipboard |
| `Space` | Toggle item checkbox for batch actions |
| `Cmd + E` | Open markup and crop editor |
| `Cmd + Return` | Save annotations and copy |
| `Cmd + Backspace` | Delete clip |
| `Esc` | Dismiss overlay or cancel edit |

---

## Tech Stack

- **UI**: SwiftUI & AppKit
- **Language**: Swift 5.9+
- **Database**: SQLite3 (WAL mode)
- **Image Processing**: CoreGraphics & Apple Vision Framework

---

## License

This project is licensed under the MIT License. See [LICENSE](LICENSE) for details.
