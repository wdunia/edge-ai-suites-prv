#!/usr/bin/env bash
# SPDX-FileCopyrightText: (C) 2026 Intel Corporation
# SPDX-License-Identifier: Apache-2.0
#
# Starts the showroom captioning runs described in pipelines.json:
#   - "camera" runs use a local USB camera device (/dev/videoX) directly
#   - "file"   runs are published as looped RTSP streams by the application's
#              own helper: live-video-captioning/scripts/setup_proxy_rtsp.sh
#
# The RTSP publisher keeps running in the background after this script returns;
# stop-all-demos.sh terminates it.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_DIR="$(cd "${SCRIPT_DIR}/../live-video-captioning" && pwd)"

CONFIG_FILE="${SCRIPT_DIR}/pipelines.json"
VIDEOS_DIR="${SCRIPT_DIR}/videos"
RTSP_CONFIG="${SCRIPT_DIR}/.rtsp-streams.json"
RTSP_PID_FILE="${SCRIPT_DIR}/.rtsp-publisher.pid"
RTSP_LOG_FILE="${SCRIPT_DIR}/.rtsp-publisher.log"
RTSP_PORT="8554"
RTSP_CONTAINER="mediamtx-server"
PIPELINE_SERVER_CONTAINER="dlstreamer-pipeline-server"

HEALTH_TIMEOUT="${HEALTH_TIMEOUT:-180}"
STREAM_READY_TIMEOUT="${STREAM_READY_TIMEOUT:-300}"

# The dashboard and its API are local; never route them through a proxy.
CURL=(curl -sS --noproxy '*')

log()  { echo "[run-pipelines] $*"; }
warn() { echo "[run-pipelines] WARNING: $*" >&2; }
die()  { echo "[run-pipelines] ERROR: $*" >&2; exit 1; }

usage() {
  cat <<EOF
Usage: $(basename "$0") [--config <file.json>] [--videos <dir>]

Options:
  --config <file>  Pipeline definitions (default: ${CONFIG_FILE})
  --videos <dir>   Directory with *.mp4 files for the "file" runs (default: ${VIDEOS_DIR})
  -h, --help       Show this help.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --config) CONFIG_FILE="${2:-}"; shift 2 ;;
    --videos) VIDEOS_DIR="${2:-}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage; exit 1 ;;
  esac
done

command -v jq >/dev/null 2>&1 || die "jq is required. Run ./install-dependencies.sh first."
[[ -f "${CONFIG_FILE}" ]] || die "Missing pipeline configuration: ${CONFIG_FILE}"
[[ -f "${APP_DIR}/.env" ]] || die "Missing ${APP_DIR}/.env. Run run-demo-captioning.sh instead."

# ---------------------------------------------------------------- environment
env_value() {
  grep -E "^$1=" "${APP_DIR}/.env" | tail -1 | cut -d= -f2-
}

HOST_IP="$(env_value HOST_IP)"; HOST_IP="${HOST_IP:-127.0.0.1}"
DASHBOARD_PORT="$(env_value DASHBOARD_PORT)"; DASHBOARD_PORT="${DASHBOARD_PORT:-4173}"
API="http://localhost:${DASHBOARD_PORT}/api"

VLM_DEVICE="$(jq -r '.vlmDevice // "gpu"' "${CONFIG_FILE}" | tr '[:upper:]' '[:lower:]')"
PIPELINE_TYPE="$(jq -r '.pipelineType // "non-detection"' "${CONFIG_FILE}")"
CAMERA_DEVICE="$(jq -r '.cameraDevice // "/dev/video0"' "${CONFIG_FILE}")"

# Top-level values act as defaults for every run; a run may override any of them.
# Frame resolution is the dominant factor for TTFT (image tokens grow with area),
# and maxNewTokens dominates the caption lag, so keep both consistent across runs.
RUN_DEFAULTS="$(jq -c '{
  frameWidth: .frameWidth,
  frameHeight: .frameHeight,
  maxNewTokens: (.maxNewTokens // 20),
  frameRate: (.frameRate // 1),
  chunkSize: (.chunkSize // 1)
}' "${CONFIG_FILE}")"

PUBLISHED_STREAMS=0

# ------------------------------------------------------------- RTSP publisher
start_rtsp_publisher() {
  local file_runs
  file_runs="$(jq '[.runs[] | select(.source == "file")] | length' "${CONFIG_FILE}")"
  if [[ "${file_runs}" -eq 0 ]]; then
    log "No file-based runs configured; skipping the RTSP publisher."
    return 0
  fi

  local videos=()
  if [[ -d "${VIDEOS_DIR}" ]]; then
    while IFS= read -r video; do
      videos+=("${video}")
    done < <(find "${VIDEOS_DIR}" -maxdepth 1 -type f -name '*.mp4' | sort)
  fi

  if [[ ${#videos[@]} -eq 0 ]]; then
    warn "No *.mp4 files found in ${VIDEOS_DIR}; only camera runs will start."
    return 0
  fi
  if [[ ${#videos[@]} -lt ${file_runs} ]]; then
    warn "Found ${#videos[@]} video file(s) for ${file_runs} configured file run(s); extra runs are skipped."
  fi

  local count=$(( ${#videos[@]} < file_runs ? ${#videos[@]} : file_runs ))
  local inputs_json outputs_json outputs=() idx
  for (( idx = 0; idx < count; idx++ )); do
    outputs+=("rtsp://${HOST_IP}:${RTSP_PORT}/stream$(( idx + 1 ))")
  done

  inputs_json="$(printf '%s\n' "${videos[@]:0:${count}}" | jq -R . | jq -s .)"
  outputs_json="$(printf '%s\n' "${outputs[@]}" | jq -R . | jq -s .)"
  jq -n --argjson inputs "${inputs_json}" --argjson outputs "${outputs_json}" \
    '{inputs: $inputs, outputs: $outputs}' > "${RTSP_CONFIG}"

  log "Publishing ${count} video file(s) as RTSP streams on ${HOST_IP}:${RTSP_PORT}"
  # setsid puts the publisher into its own process group so stop-all-demos.sh
  # can terminate it together with all of its ffmpeg children.
  setsid bash "${APP_DIR}/scripts/setup_proxy_rtsp.sh" -c "${RTSP_CONFIG}" \
    > "${RTSP_LOG_FILE}" 2>&1 &
  echo "$!" > "${RTSP_PID_FILE}"
  PUBLISHED_STREAMS="${count}"

  local waited=0
  while (( waited < 90 )); do
    if docker logs "${RTSP_CONTAINER}" 2>&1 | grep -q "publishing to path 'stream${count}'"; then
      log "RTSP streams are live."
      return 0
    fi
    sleep 2
    waited=$(( waited + 2 ))
  done
  warn "RTSP streams did not confirm publishing within ${waited}s; see ${RTSP_LOG_FILE}"
}

# ------------------------------------------------------------------- app APIs
wait_for_health() {
  log "Waiting for the captioning service to become healthy..."
  local waited=0
  while (( waited < HEALTH_TIMEOUT )); do
    if "${CURL[@]}" -m 5 "${API}/health" 2>/dev/null | grep -q healthy; then
      log "Service is healthy."
      return 0
    fi
    sleep 5
    waited=$(( waited + 5 ))
  done
  die "Service did not become healthy within ${HEALTH_TIMEOUT}s. Check: docker logs video-caption-service"
}

VLM_MODELS_JSON=""
declare -A MODEL_BY_DEVICE=()

load_models() {
  VLM_MODELS_JSON="$("${CURL[@]}" -m 10 "${API}/vlm-models")" || die "Cannot query ${API}/vlm-models"
}

# Prints the converted model for a device, or returns 1 when none exists.
model_for_device() {
  local device="$1" model
  if [[ -n "${MODEL_BY_DEVICE[${device}]:-}" ]]; then
    echo "${MODEL_BY_DEVICE[${device}]}"
    return 0
  fi
  model="$(jq -r --arg dev "${device}" \
    'first(.models[] | select((.device // "" | ascii_downcase) == $dev) | .name) // empty' <<<"${VLM_MODELS_JSON}")"
  [[ -n "${model}" ]] || return 1
  MODEL_BY_DEVICE["${device}"]="${model}"
  echo "${model}"
}

# The DL Streamer pipeline server can exit under resource pressure (see the
# application's known-issues guide). Once it is gone, every further run fails
# with a confusing DNS error, so check it explicitly.
pipeline_server_alive() {
  [[ "$(docker inspect -f '{{.State.Running}}' "${PIPELINE_SERVER_CONTAINER}" 2>/dev/null)" == "true" ]]
}

wait_stream_ready() {
  local run_id="$1" waited=0 response
  while (( waited < STREAM_READY_TIMEOUT )); do
    if ! pipeline_server_alive; then
      warn "Pipeline server exited while starting '${run_id}'."
      return 1
    fi
    response="$("${CURL[@]}" -m 10 "${API}/generate_captions_alerts/${run_id}/stream-ready" 2>/dev/null || true)"
    if [[ "$(jq -r '.error // false' <<<"${response}" 2>/dev/null || echo false)" == "true" ]]; then
      warn "Run '${run_id}' entered an error state. Check: docker logs dlstreamer-pipeline-server"
      return 1
    fi
    if [[ "$(jq -r '.ready // false' <<<"${response}" 2>/dev/null || echo false)" == "true" ]]; then
      log "Run '${run_id}' is streaming."
      return 0
    fi
    sleep 5
    waited=$(( waited + 5 ))
  done
  warn "Run '${run_id}' was not ready within ${STREAM_READY_TIMEOUT}s; continuing."
  return 0
}

start_run() {
  local run_json="$1" stream_index="${2:-}"
  local run_name source_type source_uri payload response run_id run_device model

  run_name="$(jq -r '.runName' <<<"${run_json}")"

  # A run may pin its own VLM device to spread the load across GPU and CPU.
  run_device="$(jq -r '.vlmDevice // empty' <<<"${run_json}" | tr '[:upper:]' '[:lower:]')"
  run_device="${run_device:-${VLM_DEVICE}}"
  if ! model="$(model_for_device "${run_device}")"; then
    warn "No VLM model converted for '${run_device}'; run '${run_name}' falls back to ${VLM_DEVICE^^}."
    run_device="${VLM_DEVICE}"
    model="$(model_for_device "${run_device}")"
  fi

  if [[ "$(jq -r '.source' <<<"${run_json}")" == "camera" ]]; then
    source_type="camera"
    source_uri="${CAMERA_DEVICE}"
    if [[ ! -e "${source_uri}" ]]; then
      warn "Camera device ${source_uri} not found; skipping run '${run_name}'."
      return 0
    fi
  else
    source_type="rtsp"
    source_uri="rtsp://${HOST_IP}:${RTSP_PORT}/stream${stream_index}"
  fi

  payload="$(jq -n \
    --arg url "${source_uri}" \
    --arg sourceType "${source_type}" \
    --arg pipelineType "${PIPELINE_TYPE}" \
    --arg model "${model}" \
    --arg device "${run_device}" \
    --argjson defaults "${RUN_DEFAULTS}" \
    --argjson run "${run_json}" \
    '($defaults + ($run | with_entries(select(.value != null)))) as $cfg
     | {
         rtspUrl: $url,
         streamSourceType: $sourceType,
         pipelineType: $pipelineType,
         modelName: $model,
         vlmDevice: $device,
         prompt: $cfg.prompt,
         runName: $cfg.runName,
         maxNewTokens: $cfg.maxNewTokens,
         frameRate: $cfg.frameRate,
         chunkSize: $cfg.chunkSize
       }
       + (if $cfg.frameWidth then {frameWidth: $cfg.frameWidth} else {} end)
       + (if $cfg.frameHeight then {frameHeight: $cfg.frameHeight} else {} end)')"

  if ! pipeline_server_alive; then
    die "Container '${PIPELINE_SERVER_CONTAINER}' is not running - it exited before run '${run_name}'.
Check 'docker logs ${PIPELINE_SERVER_CONTAINER}'. Common causes: too many concurrent GPU streams
or a missing no_proxy entry for ${HOST_IP} (see live-video-captioning/docs/user-guide/known-issues.md)."
  fi

  log "Starting run '${run_name}' on ${source_uri} (${run_device^^})"
  response="$("${CURL[@]}" -X POST "${API}/generate_captions_alerts" \
    -H 'Content-Type: application/json' -d "${payload}")" || {
      warn "Request failed for run '${run_name}'."
      return 0
    }

  run_id="$(jq -r '.runId // empty' <<<"${response}" 2>/dev/null || true)"
  if [[ -z "${run_id}" ]]; then
    warn "Backend rejected run '${run_name}': ${response}"
    return 0
  fi

  # Report what the backend actually applied. A run without frameWidth/frameHeight
  # is served by a *_Default_Resolution pipeline and keeps the source resolution,
  # which multiplies the image tokens and therefore the TTFT.
  log "  applied: $(jq -r '"pipeline=\(.pipelineName) resolution=\(.frameWidth // "source")x\(.frameHeight // "source") maxTokens=\(.maxTokens) frameRate=\(.frameRate) chunkSize=\(.chunkSize)"' <<<"${response}" 2>/dev/null || echo "${response}")"

  wait_stream_ready "${run_id}" || true
}

print_summary() {
  local runs
  runs="$("${CURL[@]}" -m 10 "${API}/generate_captions_alerts" 2>/dev/null || true)"
  [[ -n "${runs}" ]] || return 0
  log "Active runs:"
  jq -r '(if type == "array" then . else (.runs // []) end)[]
         | "  \(.runName // .runId): \(.pipelineName) \(.frameWidth // "source")x\(.frameHeight // "source") maxTokens=\(.maxTokens) status=\(.status)"' \
    <<<"${runs}" 2>/dev/null || true
}

# ------------------------------------------------------------------ main flow
start_rtsp_publisher
wait_for_health

load_models
if ! MODEL="$(model_for_device "${VLM_DEVICE}")"; then
  die "No VLM model available for device '${VLM_DEVICE}'. Convert one with:
  ${APP_DIR}/model_download_scripts/download_models.sh --model OpenGVLab/InternVL2-1B --type vlm --weight-format int8 --device ${VLM_DEVICE^^}"
fi
log "Default VLM model '${MODEL}' on ${VLM_DEVICE^^}"

stream_index=0
while IFS= read -r run_json; do
  if [[ "$(jq -r '.source' <<<"${run_json}")" == "file" ]]; then
    stream_index=$(( stream_index + 1 ))
    if (( stream_index > PUBLISHED_STREAMS )); then
      warn "No video published for run '$(jq -r '.runName' <<<"${run_json}")'; skipping."
      continue
    fi
    start_run "${run_json}" "${stream_index}"
  else
    start_run "${run_json}"
  fi
done < <(jq -c '.runs[]' "${CONFIG_FILE}")

print_summary
log "All configured runs have been started."

