#!/usr/bin/env python3

import argparse
import queue
import signal
import sys
from pathlib import Path

import sounddevice as sd
import soundfile as sf


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", required=True)
    parser.add_argument("--stop-file", required=True)
    parser.add_argument("--samplerate", type=int, default=16000)
    parser.add_argument("--channels", type=int, default=1)
    parser.add_argument("--subtype", default="PCM_16")
    parser.add_argument("--device", default=None)
    return parser.parse_args()


def main() -> int:
    args = parse_args()

    output_path = Path(args.output).expanduser()
    stop_path = Path(args.stop_file).expanduser()
    output_path.parent.mkdir(parents=True, exist_ok=True)
    if stop_path.exists():
        stop_path.unlink()

    audio_queue: "queue.Queue[object]" = queue.Queue()
    stopping = False

    def request_stop(*_args: object) -> None:
        nonlocal stopping
        stopping = True

    def callback(indata, frames, time_info, status) -> None:
        if status:
            print(status, file=sys.stderr)
        audio_queue.put(indata.copy())

    signal.signal(signal.SIGINT, request_stop)
    signal.signal(signal.SIGTERM, request_stop)

    try:
        with sf.SoundFile(
            str(output_path),
            mode="w",
            samplerate=args.samplerate,
            channels=args.channels,
            subtype=args.subtype,
        ) as wav_file:
            with sd.InputStream(
                samplerate=args.samplerate,
                channels=args.channels,
                dtype="int16",
                callback=callback,
                device=args.device,
            ):
                while not stopping:
                    if stop_path.exists():
                        stopping = True
                        break

                    try:
                        chunk = audio_queue.get(timeout=0.1)
                    except queue.Empty:
                        continue

                    wav_file.write(chunk)

                while True:
                    try:
                        chunk = audio_queue.get_nowait()
                    except queue.Empty:
                        break
                    wav_file.write(chunk)
    finally:
        if stop_path.exists():
            stop_path.unlink()

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
