# Perroquet

Native voice dictation for macOS. Press a shortcut, speak, and your words are typed wherever your cursor is. A personal take on [OpenWhispr](https://github.com/openwhispr/openwhispr).

> **Status:** early development.

## Features

- **Dictate anywhere:** global keyboard shortcut to start and stop recording, from any app.
- **Paste at cursor:** the transcribed text is inserted directly into the active text field.
- **Local transcription:** speech-to-text runs on your Mac with Parakeet ([FluidAudio](https://github.com/FluidInference/FluidAudio), on the Neural Engine). Audio never leaves the machine.
- **Keep or discard:** dictations are saved on your Mac for review in the Annotation tab; turn off "Save recordings" to keep nothing.
- **Menu bar app:** stays out of the way; shows when it is listening.
- **Language:** 🇬🇧 English / 🇫🇷 Français.

## Install

```sh
./install.sh
```

Builds from source (needs Xcode 26+), installs `Perroquet.app` into `/Applications` (override with `INSTALL_DIR=<dir> ./install.sh`) and leaves a zip at `build/Build/Products/Release/Perroquet.zip`.

The app is not notarized: on first launch, open System Settings › Privacy & Security and click "Open Anyway". The speech model is downloaded from Hugging Face on first launch. Grant Microphone and Accessibility access when asked.

## Requirements

- macOS 26+
- Microphone and Accessibility permissions (to record and to type into other apps)

## Development

Requires [Xcode](https://developer.apple.com/xcode/) 26+.

- `./debug.sh` builds and launches **Perroquet Dev** and quits Perroquet. It has its own bundle id, settings and dataset (`Application Support/Perroquet Dev`).
- `./install.sh` builds and installs the release app.
- `tools/make_signing_identity.sh` creates the local code-signing certificate "Perroquet", which signs both apps (run it once): with it, the Accessibility grant survives rebuilds. After switching from ad-hoc signing, remove the old Perroquet entry in System Settings › Privacy & Security › Accessibility and grant it again. Only `./debug.sh` and `./install.sh` builds keep the grant (an Xcode IDE build is signed differently).

## License

Perroquet is licensed under the MIT License. See the [LICENSE](LICENSE) file for more information.
