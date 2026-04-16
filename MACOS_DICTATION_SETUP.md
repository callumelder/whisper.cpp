# macOS Dictation Setup

This checkout now includes a local dictation workflow built on top of `whisper.cpp`.

## What is installed

- repo: `/Users/cal/dev/whisper.cpp`
- fork: `git@github.com:callumelder/whisper.cpp.git`
- branch: `mac-dictation-setup`
- models:
  - `models/ggml-small.en.bin`
  - `models/ggml-base.en.bin`
  - `models/ggml-silero-v6.2.0.bin`
  - `models/ggml-small.en-encoder.mlmodelc`
- build flags:
  - `WHISPER_COREML=1`
  - `WHISPER_SDL2=ON`

## Default dictation behavior

- hold `control + option`
- while both keys are down: record from the current macOS default microphone
- when you release either key: stop recording immediately, transcribe locally, and paste the text into the frontmost app
- default model: `small.en` with VAD and Core ML encoder acceleration
- recorder: Python `sounddevice` + `soundfile`

## Helper commands

List audio devices:

```bash
/Users/cal/dev/whisper.cpp/tools/macos-dictation/list-audio-devices.sh
```

Transcribe an audio file manually:

```bash
/Users/cal/dev/whisper.cpp/tools/macos-dictation/transcribe-file.sh /path/to/audio.wav
```

## Local macOS files

- Hammerspoon loader: `/Users/cal/.hammerspoon/init.lua`
- Hammerspoon module: `/Users/cal/dev/whisper.cpp/tools/macos-dictation/hammerspoon/whisper_dictation.lua`
- LaunchAgent: `/Users/cal/Library/LaunchAgents/com.callumelder.hammerspoon.plist`

## If anything needs one last click

When you return, macOS may still ask Hammerspoon for:

- Accessibility access, so it can paste into the active app
- Microphone access, if macOS attributes mic capture to Hammerspoon rather than the spawned Python recorder

If the hotkey does nothing, open `Hammerspoon.app` once and accept those prompts.
