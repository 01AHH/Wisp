# Wisp

A stripped-down [Wispr Flow](https://wisprflow.ai) for macOS — a regular windowed app with a Dock icon.
Hold a key, talk, let go — the words appear wherever your cursor is. Runs entirely on-device with Apple's macOS 26 speech engine, so there is
no account, no API key and nothing sent anywhere.

## How it works

1. **Hold `fn`** (or right ⌥ / ⌘ / ⌃ — pick in the menu). A small pill appears at the bottom of the screen with a live waveform.
2. **Talk.**
3. **Let go.** Wisp transcribes, tidies the text (capital letter, punctuation, filler words like "um" removed) and pastes it into the app you were in. Your clipboard is restored afterwards.

A tap shorter than a quarter second is ignored so brushing the key does nothing.

## Install

```bash
./scripts/build-app.sh --install     # builds Wisp.app and puts it in /Applications
```

Only the Xcode Command Line Tools are needed (no Xcode). Requires macOS 26.

On first launch:

- **Microphone** — approve the prompt.
- **Accessibility** — System Settings → Privacy & Security → Accessibility → turn on Wisp.
  This is what lets Wisp see the held key and paste into other apps.
- The first run downloads Apple's speech model for your language (a one-off, a few hundred MB).

If you use the `fn` key, set *System Settings → Keyboard → "Press 🌐 key to"* to **Do Nothing** so
macOS doesn't fight over it.

## The window

- **Status header** — ready / listening (with a live waveform) / transcribing, and which mic is active.
- **Scratchpad** (left) — dictate into it while the window is focused, edit the text, then hit
  **Pull Through** (⌘↩): Wisp hides, the app you came from gets focus and the text is pasted there.
  **Recent** lists your last 20 dictations so you can drop one back in. Contents persist.
- **Settings** (right) — open Wisp at login, hold key, filler-word removal, which microphone to
  record from, **Test Microphone** (records three seconds and shows what came through), and
  permission status with Grant buttons. The login toggle only works from the installed Wisp.app,
  not from `swift run`.

Closing the window keeps dictation running in the background; click the Dock icon to bring it
back. ⌘Q quits.

## Notes

- **Lid closed?** macOS disables the built-in microphone in clamshell mode. The pill will say
  "No sound from MacBook Pro Microphone" — pick another mic in the Microphone menu.
- **AirPods / Bluetooth mics** take a second or two to switch into headset mode after you press the
  key. The pill says "Connecting mic…" until audio is actually flowing — start talking when the
  waveform appears.
- A log of each session is written to `~/Library/Logs/Wisp.log`.
- `Wisp --selftest <file>` records 4 s from the mic and writes the transcript to `<file>` (used for
  debugging without the hotkey).

## Layout

```
Sources/Wisp/
  WispApp.swift        app lifecycle, main menu, press/release → transcribe → paste
  MainWindow.swift     the window: status header, scratchpad, settings column
  AppModel.swift       observable state for the window
  HoldKeyMonitor.swift CGEventTap watching one modifier key
  Transcriber.swift    AVCaptureSession mic → SpeechAnalyzer (on-device)
  AudioDevices.swift   CoreAudio input device list + selection
  TextCleaner.swift    fillers, capitalisation, trailing space
  TextInserter.swift   paste via ⌘V, restore clipboard
  Overlay.swift        the floating pill
  Scratchpad.swift     scratchpad logic + view, recent dictations, pull-through
  Settings.swift       UserDefaults
  LaunchAtLogin.swift  login item via SMAppService
  Log.swift            ~/Library/Logs/Wisp.log
```
