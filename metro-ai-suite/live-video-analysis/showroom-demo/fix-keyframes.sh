#!/bin/bash
# Re-encodes all MP4 files in a directory with keyframes every 1 second.
# Usage: ./fix-keyframes.sh ./videos/
# Output files replace originals (originals backed up as .bak).

set -e

if [ -z "$1" ]; then
  echo "Usage: $0 <video_directory>"
  exit 1
fi

VIDEO_DIR="$1"
FPS=30
GOP=$FPS  # keyframe every 1 second

for f in "$VIDEO_DIR"/*.mp4; do
  [ -f "$f" ] || continue
  [[ "$f" == *_looped.mp4 ]] && continue

  echo "Processing: $f"
  tmp="${f%.mp4}_fixed.mp4"

  ffmpeg -y -i "$f" \
    -c:v libx264 -preset fast -crf 23 \
    -r "$FPS" -g "$GOP" -keyint_min "$GOP" \
    -an "$tmp"

  mv "$f" "${f}.bak"
  mv "$tmp" "$f"
  echo "  Done (original saved as ${f}.bak)"
done

echo "All files processed."

