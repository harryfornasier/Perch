# Frigate Native

A native OS X Snow Leopard application for monitoring a [Frigate NVR](https://frigate.video) instance. Built with Objective-C and Cocoa — no dependencies, no runtime, just a double-clickable `.app`.

![Platform](https://img.shields.io/badge/platform-OS%20X%2010.6%2B-lightgrey)
![Language](https://img.shields.io/badge/language-Objective--C-blue)

## Features

- **Live view** — polls your cameras at 2fps via Frigate's JPEG snapshot API
- **Events** — browsable list of recent events with thumbnails and in-app clip playback (QTKit)
- **Detections** — live table of person detections with confidence scores and zones
- **Notifications** — Growl alerts when a new person detection arrives
- **Preferences** — configure your Frigate URL at runtime; persists across launches

## Requirements

- OS X 10.6 Snow Leopard (also works on later versions)
- Xcode 3.2 or later with Command Line Tools
- A running [Frigate](https://frigate.video) instance on your local network
- [Growl](https://growl.github.io/growl/) + `growlnotify` for notifications (optional)

## Building

```bash
cd FrigateNative
chmod +x build.sh
./build.sh
```

This produces `Frigate Native.app` in the same folder. Double-click to launch.

No third-party libraries or package managers are required.

## Configuration

On first launch, go to the **Preferences** tab and enter your Frigate URL (e.g. `http://192.168.1.x:5000`). Click **Save & Reconnect** — the URL is stored in your user preferences and remembered on every subsequent launch.

You can also use **Test Connection** to verify a URL before saving.

## Notifications

Growl notifications require the `growlnotify` command-line tool, installed at either:

- `/usr/local/bin/growlnotify`
- `/opt/local/bin/growlnotify` (MacPorts)

If `growlnotify` is not found, the app runs normally without notifications.

## Project Structure

```
FrigateNative/
├── main.m            — Entry point
├── AppDelegate.h/m   — All UI (programmatic Cocoa, no NIB)
├── FrigateAPI.h/m    — Frigate HTTP client
├── SimpleJSON.h/m    — Lightweight JSON parser (NSJSONSerialization requires 10.7+)
├── Info.plist        — App bundle metadata
├── AppIcon.icns      — Application icon
└── build.sh          — Compile script
```

## Notes

- Uses manual memory management (no ARC) for Snow Leopard compatibility
- Video playback uses QTKit, which handles local H.264 MP4 natively
- JSON parsing is handled by a custom recursive-descent parser since `NSJSONSerialization` was not available until OS X 10.7

## License

MIT

---

> This project was built with [Claude](https://claude.ai) by Anthropic.
