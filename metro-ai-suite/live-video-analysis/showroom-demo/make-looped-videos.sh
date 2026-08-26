#!/usr/bin/env bash
# SPDX-FileCopyrightText: (C) 2026 Intel Corporation
# SPDX-License-Identifier: Apache-2.0
#
# Creates long, pre-looped copies of the demo clips.
#
# The demo publishes videos/*.mp4 as RTSP streams with the application helper
# (live-video-captioning/scripts/setup_proxy_rtsp.sh), which loops the file with
# `ffmpeg -re -stream_loop -1`. Every loop wrap is a timestamp discontinuity for
# the consuming pipeline. Feeding it a clip that is already several hours long
# removes those wraps for the duration of a showroom day, without changing
# anything in the application or in the demo runtime flow.
#
# Usage:
#   ./make-looped-videos.sh --hours 6 source/intersection.mp4
#   ./make-looped-videos.sh --hours 6 --input-dir source --output-dir videos
#
# The result is written to videos/<name>_<hours>h.mp4, which is exactly what
# run-pipelines.sh picks up.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

HOURS="4"
OUTPUT_DIR="${SCRIPT_DIR}/videos"
INPUT_DIR=""
REENCODE=0
FORCE=0
INPUTS=()

log()  { echo "[loop-videos] $*"; }
warn() { echo "[loop-videos] WARNING: $*" >&2; }
die()  { echo "[loop-videos] ERROR: $*" >&2; exit 1; }

usage() {
  cat <<EOF
Usage: $(basename "$0") [options] [<video.mp4> ...]

Options:
  --hours <n>         Target length of the looped file in hours (default: ${HOURS}).
                      Accepts decimals, e.g. 0.5 for a quick test.
  --input-dir <dir>   Loop every *.mp4 found in this directory.
  --output-dir <dir>  Where to write the results (default: ${OUTPUT_DIR}).
  --reencode          Re-encode instead of copying the video stream. Slower, but
                      produces a uniform 30 fps / 2 s-GOP H.264 baseline file -
                      use it when the source clips have odd frame rates or very
                      sparse keyframes.
  --force             Overwrite existing output files.
  -h, --help          Show this help.

Notes:
  * Audio is dropped: the captioning pipelines consume video only, and a looped
    audio track is a common source of timestamp problems.
  * Copy mode is nearly instant and keeps the original quality; the output size
    grows linearly with the requested length - check the estimate it prints.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --hours)      HOURS="${2:-}"; shift 2 ;;
    --input-dir)  INPUT_DIR="${2:-}"; shift 2 ;;
    --output-dir) OUTPUT_DIR="${2:-}"; shift 2 ;;
    --reencode)   REENCODE=1; shift ;;
    --force)      FORCE=1; shift ;;
    -h|--help)    usage; exit 0 ;;
    -*) echo "Unknown option: $1" >&2; usage; exit 1 ;;
    *) INPUTS+=("$1"); shift ;;
  esac
done

command -v ffmpeg  >/dev/null 2>&1 || die "ffmpeg is required. Run ./install-dependencies.sh first."
command -v ffprobe >/dev/null 2>&1 || die "ffprobe is required. Run ./install-dependencies.sh first."

[[ "${HOURS}" =~ ^[0-9]+([.][0-9]+)?$ ]] || die "--hours must be a number, got '${HOURS}'"
TARGET_SECONDS="$(awk -v h="${HOURS}" 'BEGIN { printf "%d", h * 3600 }')"
(( TARGET_SECONDS > 0 )) || die "--hours must be greater than 0"

if [[ -n "${INPUT_DIR}" ]]; then
  [[ -d "${INPUT_DIR}" ]] || die "Input directory does not exist: ${INPUT_DIR}"
  while IFS= read -r file; do
    INPUTS+=("${file}")
  done < <(find "${INPUT_DIR}" -maxdepth 1 -type f -name '*.mp4' | sort)
fi

[[ ${#INPUTS[@]} -gt 0 ]] || { echo "No input videos given." >&2; usage; exit 1; }

mkdir -p "${OUTPUT_DIR}"

human_size() { numfmt --to=iec --suffix=B "$1" 2>/dev/null || echo "${1} bytes"; }

free_bytes() {
  df -B1 --output=avail "${OUTPUT_DIR}" 2>/dev/null | tail -1 | tr -d ' '
}

for input in "${INPUTS[@]}"; do
  [[ -f "${input}" ]] || { warn "Skipping missing file: ${input}"; continue; }

  base="$(basename "${input}")"
  name="${base%.*}"
  # Do not loop a file that this script already produced.
  if [[ "${name}" =~ _[0-9]+(\.[0-9]+)?h$ ]]; then
    warn "Skipping already looped file: ${base}"
    continue
  fi

  output="${OUTPUT_DIR}/${name}_${HOURS}h.mp4"
  if [[ -f "${output}" && "${FORCE}" -ne 1 ]]; then
    log "Exists, skipping (use --force to overwrite): ${output}"
    continue
  fi

  duration="$(ffprobe -v error -show_entries format=duration -of csv=p=0 "${input}" 2>/dev/null || echo "")"
  size="$(stat -c %s "${input}" 2>/dev/null || echo 0)"
  if [[ -n "${duration}" && "${duration}" != "N/A" ]] && (( size > 0 )); then
    estimate="$(awk -v s="${size}" -v d="${duration}" -v t="${TARGET_SECONDS}" \
      'BEGIN { printf "%d", (d > 0 ? s / d * t : 0) }')"
    avail="$(free_bytes)"
    log "${base}: $(printf '%.0f' "${duration}")s source -> ${TARGET_SECONDS}s output, ~$(human_size "${estimate}") needed"
    if [[ -n "${avail}" ]] && (( estimate > 0 )) && (( avail < estimate )); then
      warn "Only $(human_size "${avail}") free in ${OUTPUT_DIR} - lower --hours or free up space."
    fi
  fi

  log "Writing ${output} ..."
  if [[ "${REENCODE}" -eq 1 ]]; then
    # Uniform 30 fps with a keyframe every 2 s, matching what the RTSP publisher
    # produces at runtime; H.264 baseline/yuv420p is what the pipelines decode.
    ffmpeg -hide_banner -y -nostdin \
      -fflags +genpts -stream_loop -1 -i "${input}" \
      -t "${TARGET_SECONDS}" \
      -an -map 0:v:0 \
      -c:v libx264 -preset veryfast -crf 23 \
      -profile:v baseline -level 3.1 -pix_fmt yuv420p \
      -r 30 -g 60 -keyint_min 30 \
      -movflags +faststart \
      "${output}"
  else
    # Stream copy: fast and lossless. +genpts rebuilds a continuous timestamp
    # sequence across the loop boundaries.
    ffmpeg -hide_banner -y -nostdin \
      -fflags +genpts -stream_loop -1 -i "${input}" \
      -t "${TARGET_SECONDS}" \
      -an -map 0:v:0 -c:v copy \
      -avoid_negative_ts make_zero \
      -movflags +faststart \
      "${output}"
  fi

  out_duration="$(ffprobe -v error -show_entries format=duration -of csv=p=0 "${output}" 2>/dev/null || echo "?")"
  out_size="$(stat -c %s "${output}" 2>/dev/null || echo 0)"
  log "Done: ${output} ($(printf '%.0f' "${out_duration:-0}")s, $(human_size "${out_size}"))"
done

log "All files processed. Point the demo at them with:"
log "  ./run-pipelines.sh --videos ${OUTPUT_DIR}"

