#!/bin/zsh

set -euo pipefail

if [ "$#" -ne 1 ]; then
  echo "usage: $0 <audio-file>" >&2
  exit 1
fi

get_script_path() {
  local script_source="${(%):-%x}"

  if [ -x "$(command -v realpath)" ]; then
    dirname "$(realpath "$script_source")"
  else
    (cd -- "$(dirname "$script_source")" >/dev/null 2>&1 || exit 1; pwd -P)
  fi
}

repo_root="$(cd "$(get_script_path)/../.." && pwd)"
audio_file="$1"

cli="${WHISPER_DICTATION_CLI:-$repo_root/build/bin/whisper-cli}"
model="${WHISPER_DICTATION_MODEL:-$repo_root/models/ggml-small.en.bin}"
vad_model="${WHISPER_DICTATION_VAD_MODEL:-$repo_root/models/ggml-silero-v6.2.0.bin}"
threads="${WHISPER_DICTATION_THREADS:-8}"
language="${WHISPER_DICTATION_LANGUAGE:-en}"

if [ ! -x "$cli" ]; then
  echo "whisper-cli not found at $cli" >&2
  exit 1
fi

if [ ! -f "$model" ]; then
  echo "model not found at $model" >&2
  exit 1
fi

if [ ! -f "$vad_model" ]; then
  echo "VAD model not found at $vad_model" >&2
  exit 1
fi

if [ ! -f "$audio_file" ]; then
  echo "audio file not found at $audio_file" >&2
  exit 1
fi

if [ ! -s "$audio_file" ]; then
  exit 0
fi

raw_text="$("$cli" \
  -m "$model" \
  -vm "$vad_model" \
  --vad \
  -f "$audio_file" \
  -nt \
  -np \
  -l "$language" \
  -t "$threads")"

printf '%s\n' "$raw_text" | tr '\r\n' ' ' | sed -E 's/[[:space:]]+/ /g; s/^ //; s/ $//'
