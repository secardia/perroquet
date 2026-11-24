# Perroquet

Native voice dictation for macOS. Press a shortcut, speak, and your words are typed wherever your cursor is. A personal take on [OpenWhispr](https://github.com/openwhispr/openwhispr).

> **Status:** early development. Nothing to install yet.

## Features

- **Dictate anywhere:** global keyboard shortcut to start and stop recording, from any app.
- **Paste at cursor:** the transcribed text is inserted directly into the active text field.
- **Local transcription:** speech-to-text runs on your Mac with Whisper models. Audio never leaves the machine.
- **Cloud option:** use a remote transcription API instead, if you prefer speed or accuracy over privacy.
- **Cleanup:** optional pass by an AI model to fix punctuation, filler words, and formatting.
- **History:** past transcriptions kept locally, easy to copy again.
- **Menu bar app:** stays out of the way; shows when it is listening.
- **Language:** 🇬🇧 English / 🇫🇷 Français.

## Requirements

- macOS 26+
- Microphone and Accessibility permissions (to record and to type into other apps)

## Development

Requires [Xcode](https://developer.apple.com/xcode/) 26+.

- `./run.sh` builds and launches the app.
- `tools/make_signing_identity.sh` creates a local code-signing certificate (run it once): with it, the Accessibility grant survives rebuilds. After switching from ad-hoc signing, remove the old Perroquet entry in System Settings › Privacy & Security › Accessibility and grant it again. Only `./run.sh` builds keep the grant (an Xcode IDE build is signed differently).
- `python3 tools/import_oriloq.py` imports the Oriloq recordings (and their annotations) into the dataset; safe to re-run.

## License

Perroquet is licensed under the MIT License. See the [LICENSE](LICENSE) file for more information.
