#!/usr/bin/env bash
# Trim the recorded demo segment, burn Chinese captions, encode H.264.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FRAMES="${1:-$ROOT/frames/install}"
OUT="${2:-$ROOT/pcl-2.99.0.1-poc-demo.mp4}"
TIMELINE="${TIMELINE:-$ROOT/evidence/demo-timeline.csv}"
SRT="$ROOT/demo.srt"
TRIM="$ROOT/trim.json"

python3 "$ROOT/make_srt.py" \
    --frames "$FRAMES/index.csv" \
    --timeline "$TIMELINE" \
    --captions "$ROOT/subtitles/captions.tsv" \
    --out "$SRT" \
    --trim "$TRIM"

FPS="$(python3 -c 'import json; print(json.load(open("'"$TRIM"'"))["fps"])')"
START="$(python3 -c 'import json; print(json.load(open("'"$TRIM"'"))["start_frame"])')"
COUNT="$(python3 -c 'import json; print(json.load(open("'"$TRIM"'"))["frames"])')"

cd "$ROOT"
ffmpeg -y -hide_banner \
    -framerate "$FPS" -start_number "$START" \
    -i "$FRAMES/frame-%06d.jpg" \
    -frames:v "$COUNT" \
    -vf "subtitles=demo.srt:force_style='FontName=Noto Sans CJK SC,FontSize=9,PrimaryColour=&H00FFFFFF,OutlineColour=&H00000000,BorderStyle=1,Outline=1,Shadow=0,MarginV=18'" \
    -c:v libx264 -preset veryfast -crf 20 -pix_fmt yuv420p \
    -movflags +faststart "$OUT"

echo "wrote $OUT"
