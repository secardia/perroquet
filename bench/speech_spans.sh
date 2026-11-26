#!/bin/sh
# Writes speech_spans.json (Silero VAD speech, padded by 1 s, as the app) for every prod and dev recording that lacks one.
# The app writes it for each new dictation; this backfills older recordings, or redoes all with --force.
set -e
cd "$(dirname "$0")"
swift build --package-path fluidbench -c release --product speechspans
SUPPORT="$HOME/Library/Application Support"
fluidbench/.build/release/speechspans "$@" \
  "$SUPPORT/Perroquet/FineTuningDataset" \
  "$SUPPORT/Perroquet Dev/FineTuningDataset"
