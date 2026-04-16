#!/bin/zsh

set -euo pipefail

if [ "$#" -lt 3 ] || [ "$#" -gt 4 ]; then
  echo "usage: $0 <audio-file> <mic-index> <stop-file> [ffmpeg-bin]" >&2
  exit 1
fi

audio_file="$1"
mic_index="$2"
stop_file="$3"
ffmpeg_bin="${4:-/opt/homebrew/bin/ffmpeg}"

mkdir -p "$(dirname "$audio_file")"
rm -f "$stop_file"

"$ffmpeg_bin" \
  -hide_banner \
  -loglevel error \
  -y \
  -f avfoundation \
  -i ":$mic_index" \
  -ac 1 \
  -ar 16000 \
  -c:a pcm_s16le \
  "$audio_file" &

ffmpeg_pid=$!

function cleanup {
  if kill -0 "$ffmpeg_pid" >/dev/null 2>&1; then
    /bin/kill -INT "$ffmpeg_pid" >/dev/null 2>&1 || true
    wait "$ffmpeg_pid" || true
  fi

  rm -f "$stop_file"
}

trap cleanup EXIT INT TERM

while kill -0 "$ffmpeg_pid" >/dev/null 2>&1; do
  if [ -f "$stop_file" ]; then
    /bin/kill -INT "$ffmpeg_pid" >/dev/null 2>&1 || true
    wait "$ffmpeg_pid" || true
    exit 0
  fi

  sleep 0.1
done

wait "$ffmpeg_pid" || true
