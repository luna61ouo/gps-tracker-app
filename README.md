# claw GPS Tracker

Privacy-first GPS tracking companion for [OpenClaw](https://github.com/openclaw).

Your phone sends end-to-end encrypted GPS coordinates to your own computer through a zero-storage relay. No cloud, no third-party servers storing your location — all data stays on your machine.

## How it works

```
Phone App (this repo)
  │  Encrypt GPS with X25519 + AES-256-GCM
  ▼
gps-relay (zero-storage, forwards only)
  │
  ▼
gps-bridge (your computer)
  │  Decrypt → store in local SQLite
  ▼
OpenClaw queries your location
```

## Features

- **End-to-end encryption** — X25519 key exchange + AES-256-GCM, new ephemeral key per message
- **Background GPS tracking** — continues when app is minimized (iOS location stream / Android foreground service)
- **Configurable intervals** — update frequency from 5 seconds to 30 minutes
- **History recording** — adjustable granularity and retention period
- **Sharing modes** — Auto (continuous), Ask (coming soon), Deny (stops all transmission)
- **Multi-language** — Traditional Chinese and English
- **Open source** — phone app, relay, and bridge are all publicly auditable

## Privacy

- The relay server is zero-storage — it only forwards encrypted blobs
- Your private key never leaves your computer
- GPS data is stored only on your machine
- No account required, no telemetry, no ads

## Requirements

- iOS 13+ or Android 8+
- A computer running [gps-bridge](https://github.com/luna61ouo/gps-bridge)

## Setup

1. Install [gps-bridge](https://github.com/luna61ouo/gps-bridge) on your computer
2. Tell OpenClaw: "I want to set up GPS tracking"
3. OpenClaw generates a pairing token and public key
4. Enter them in the app's Settings → Pairing section
5. Tap Start Tracking — done!

Or see the [gps-bridge setup guide](https://github.com/luna61ouo/gps-bridge#quick-start) for manual setup.

## Building from source

```bash
git clone https://github.com/luna61ouo/gps-tracker-app.git
cd gps-tracker-app

# Copy and edit the config file
cp lib/config.dart.example lib/config.dart
# Edit lib/config.dart with your relay URL

# Run
flutter pub get
flutter run
```

## Related projects

| Project | Description |
|---------|-------------|
| [gps-bridge](https://github.com/luna61ouo/gps-bridge) | Encrypted GPS receiver for your computer |
| [gps-relay](https://github.com/luna61ouo/gps-relay) | Zero-storage WebSocket relay server |
| [gps-geocoder-tw](https://github.com/luna61ouo/gps-geocoder-tw) | Offline reverse geocoder for Taiwan |

## License

MIT
