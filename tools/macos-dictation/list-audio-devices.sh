#!/bin/zsh

set -euo pipefail

ffmpeg_bin="${WHISPER_DICTATION_FFMPEG:-/opt/homebrew/bin/ffmpeg}"

if [ ! -x "$ffmpeg_bin" ]; then
  echo "ffmpeg not found at $ffmpeg_bin" >&2
  exit 1
fi

"$ffmpeg_bin" -f avfoundation -list_devices true -i "" 2>&1 \
  | awk '
      /AVFoundation audio devices:/ { show = 1; next }
      /Error opening input/ { next }
      show && /^\[AVFoundation indev/ { print }
    '
