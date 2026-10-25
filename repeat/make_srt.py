#!/usr/bin/env python3
"""Build demo.srt and trim.json from demo-timeline.csv + frames/index.csv."""

import argparse
import csv
import json
import os


def read_index(path):
    frames = []
    with open(path, encoding="utf-8-sig", newline="") as handle:
        for row in csv.DictReader(handle):
            frames.append((int(row["frame"]), int(row["epoch_ms"])))
    if not frames:
        raise SystemExit("empty frames index: %s" % path)
    return frames


def read_timeline(path):
    events = []
    with open(path, encoding="utf-8-sig", newline="") as handle:
        for row in csv.reader(handle):
            if len(row) >= 2 and row[0].strip():
                events.append((row[0].strip(), int(row[1])))
    if not events:
        raise SystemExit("empty timeline: %s" % path)
    return events


def read_captions(path):
    captions = {}
    with open(path, encoding="utf-8-sig") as handle:
        for line in handle:
            line = line.rstrip("\r\n")
            if not line or line.startswith("#"):
                continue
            key, _, value = line.partition("\t")
            if key and value:
                captions[key.strip()] = value.strip()
    return captions


def stamp(ms):
    ms = max(0, int(round(ms)))
    hours, rem = divmod(ms, 3600_000)
    minutes, rem = divmod(rem, 60_000)
    seconds, millis = divmod(rem, 1000)
    return "%02d:%02d:%02d,%03d" % (hours, minutes, seconds, millis)


def nearest_frame(frames, epoch_ms):
    return min(frames, key=lambda item: abs(item[1] - epoch_ms))


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--frames", required=True, help="frames/index.csv")
    parser.add_argument("--timeline", required=True, help="demo-timeline.csv")
    parser.add_argument("--captions", required=True, help="captions.tsv")
    parser.add_argument("--out", required=True, help="output .srt")
    parser.add_argument("--trim", required=True, help="output trim.json")
    parser.add_argument("--start", default="step1")
    parser.add_argument("--post", type=float, default=12.0)
    args = parser.parse_args()

    frames = read_index(args.frames)
    events = read_timeline(args.timeline)
    captions = read_captions(args.captions)
    events = [(key, ms) for key, ms in events if key in captions]
    if not events:
        raise SystemExit("no captioned events in timeline")

    start_index = next((i for i, (key, _) in enumerate(events) if key == args.start), None)
    if start_index is None:
        raise SystemExit("start event %r not in timeline" % args.start)

    start_frame, start_epoch = nearest_frame(frames, events[start_index][1])
    end_epoch = events[-1][1] + int(args.post * 1000)
    end_frame, _ = nearest_frame(frames, end_epoch)
    end_frame = max(start_frame, min(end_frame, frames[-1][0]))

    span = (frames[-1][1] - frames[0][1]) / 1000.0
    fps = (len(frames) - 1) / span if span > 0 else 8.0
    fps = max(1.0, min(30.0, fps))

    cues = []
    for i in range(start_index, len(events)):
        key, epoch_ms = events[i]
        begin = max(0.0, (epoch_ms - start_epoch) / 1000.0)
        if i + 1 < len(events):
            finish = max(begin + 0.8, (events[i + 1][1] - start_epoch) / 1000.0)
        else:
            finish = max(begin + 3.0, (end_epoch - start_epoch) / 1000.0)
        cues.append((begin, finish, captions[key]))

    with open(args.out, "w", encoding="utf-8") as handle:
        for index, (begin, finish, text) in enumerate(cues, 1):
            handle.write("%d\n%s --> %s\n%s\n\n" % (index, stamp(begin * 1000), stamp(finish * 1000), text))

    trim = {
        "start_frame": start_frame,
        "end_frame": end_frame,
        "frames": end_frame - start_frame + 1,
        "fps": round(fps, 4),
        "duration": round((end_epoch - start_epoch) / 1000.0, 3),
        "start_epoch_ms": start_epoch,
        "end_epoch_ms": end_epoch,
    }
    with open(args.trim, "w", encoding="utf-8") as handle:
        json.dump(trim, handle, indent=2)
        handle.write("\n")

    print(json.dumps(trim, indent=2))
    print("wrote %s and %s" % (args.out, args.trim))


if __name__ == "__main__":
    main()
