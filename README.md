# TROLLfx Mac EQ v0.2 — Intel Monterey

Standalone audio player focused on advanced parametric EQ. Native SwiftUI + Apple Core Audio; no third-party binary dependencies. Source is MIT licensed.

**Target:** Intel x86_64, macOS 12.6.4, Xcode 14.2 (Swift 5.7).

## Features
- 10 independently configurable filters: Peak, Low Shelf, High Shelf, High Pass, Low Pass
- Each band has logarithmic frequency (20 Hz–20 kHz), gain (±18 dB), Q (0.20–12), and enable/bypass
- Preamp −30 to +12 dB, global EQ bypass, response graph, Flat/Warm/Presence/Bass/Vocal presets
- JSON import/export for full EQ profiles, separate A/B comparison slots and copy function
- Native AVAudioEngine / AVAudioUnitEQ local file playback (WAV, AIFF, CAF, MP3, M4A subject to system codec support)

## Build on an Intel Mac
Install Xcode 14.2 (with command-line tools) and open Terminal in this folder:

```bash
chmod +x scripts/build-app.sh
./scripts/build-app.sh
open 'dist/TROLLfx Mac EQ.app'
```

The builder targets x86_64 and packages an unsigned `.app`; the Mac may require right-click → Open for the first launch. No Mac build, hardware audio test, or signing was possible in the Linux generation environment.

## How to use
1. Open Audio and choose a local supported audio file.
2. Drag the frequency, gain and Q controls; choose Peak/Shelf/Pass in each row.
3. Set preamp low enough to avoid clipping from boosts.
4. Use A/B slots to compare EQ settings; use Save EQ to export a `.json` preset.

## Engineering notes
Apple's `AVAudioUnitEQ` implements the actual DSP. Its `bandwidth` property accepts **octaves**, not conventional Q, so the app translates Q using an analog bandwidth approximation; the exact shape may differ from textbook biquad curves. The graph uses a perceptual estimate rather than measurements of Apple's filter transfer functions, especially for pass filters. Do not treat it as a calibrated measurement. The DSP and graph are separate.

Current limitations: standalone files only (not system-wide audio), no timeline scrub/pause, no playlist, no loudness meter, no offline export, no AU plugin hosting, and no signed installer. Playback uses stop/replay from the beginning. No third-party code is bundled. JSON is validated for bounds and band IDs before applying.

## License
MIT for this repository's original code. Apple frameworks follow Apple's terms.
