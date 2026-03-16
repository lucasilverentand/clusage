<p align="center">
  <img src="Resources/Assets.xcassets/AppIcon.appiconset/icon_256x256.png" width="128" height="128" alt="Clusage app icon">
</p>

<h1 align="center">Clusage</h1>

<p align="center">
  <strong>Claude usage tracking for your menu bar</strong><br>
  Monitor your 5-hour and 7-day rate limit windows, see momentum and projections, and never get surprised by a rate limit again.
</p>

<p align="center">
  <a href="https://github.com/seventwo-studio/clusage/releases/latest"><img src="https://img.shields.io/github/v/release/seventwo-studio/clusage?style=flat-square" alt="Latest Release"></a>
  <img src="https://img.shields.io/badge/platform-macOS_26+-blue?style=flat-square" alt="macOS 26+">
  <img src="https://img.shields.io/github/license/seventwo-studio/clusage?style=flat-square" alt="MIT License">
</p>

## Install

### Homebrew (recommended)

```bash
brew install seventwo-studio/tap/clusage
```

### Manual Download

**[Download the latest release](https://github.com/seventwo-studio/clusage/releases/latest)**

1. Download `Clusage.dmg` from the latest release
2. Open the DMG and drag **Clusage** to your Applications folder
3. Launch Clusage — it lives in your menu bar
4. Follow the onboarding to import your Claude Code credentials from the keychain

> Clusage requires macOS 26 (Tahoe) or later.

## Features

- **Real-time usage tracking** — 5-hour and 7-day rate limit windows with auto-polling
- **Menu bar icon** — always-visible usage at a glance
- **Momentum engine** — velocity, acceleration, ETA to ceiling, burst detection
- **7-day projections** — projected usage at reset, daily budget, pacing status
- **Granular 7-day tracking** — sub-integer interpolation between API ticks
- **Smart polling** — adapts frequency based on activity, detects Claude processes, respects rate limits
- **Dashboard** — detailed gauges, charts, and account info in a transparent window
- **Widget** — macOS widget for quick usage checks
- **Multi-account** — track multiple Claude accounts simultaneously
- **ClaudeLine integration** — exposes `~/.claude/clusage-api.json` for [ClaudeLine](https://github.com/nicekid1/claudeline) status line components

## ClaudeLine Integration

Clusage integrates with [ClaudeLine](https://github.com/nicekid1/claudeline) by writing usage data to `~/.claude/clusage-api.json`. ClaudeLine picks this up automatically — no extra configuration needed.

## Building from Source

Requires [Tuist](https://tuist.io) and Xcode with Swift 6.2 support.

```bash
git clone https://github.com/seventwo-studio/clusage.git
cd clusage
tuist generate --no-open
xcodebuild -scheme Clusage -configuration Release build
```

## License

MIT
