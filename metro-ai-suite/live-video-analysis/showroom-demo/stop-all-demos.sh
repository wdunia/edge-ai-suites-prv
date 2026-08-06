#!/usr/bin/env bash
# SPDX-FileCopyrightText: (C) 2026 Intel Corporation
# SPDX-License-Identifier: Apache-2.0
#
# Stops the showroom demo: application stack, RTSP publisher and its
# simulated-stream container. Called automatically by run-demo-captioning.sh
# before starting and while shutting down.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_DIR="$(cd "${SCRIPT_DIR}/../live-video-captioning" && pwd)"
DEMO_ENV="${SCRIPT_DIR}/captioning-demo.env"
RTSP_PID_FILE="${SCRIPT_DIR}/.rtsp-publisher.pid"
RTSP_CONFIG="${SCRIPT_DIR}/.rtsp-streams.json"
RTSP_CONTAINER="mediamtx-server"
BROWSER_PID_FILE="${SCRIPT_DIR}/.browser.pid"
BROWSER_PROFILE_DIR="${SCRIPT_DIR}/.browser-profile"

# Close the kiosk browser window started by run-demo-captioning.sh so the next
# run always opens a fresh window instead of reusing the old tab.
if [[ -f "${BROWSER_PID_FILE}" ]]; then
  echo "Closing demo browser..."
  bpid="$(cat "${BROWSER_PID_FILE}")"
  if [[ -n "${bpid}" ]]; then
    kill -TERM "-${bpid}" 2>/dev/null || kill -TERM "${bpid}" 2>/dev/null || true
    sleep 1
    kill -KILL "-${bpid}" 2>/dev/null || kill -KILL "${bpid}" 2>/dev/null || true
  fi
  rm -f "${BROWSER_PID_FILE}"
fi
rm -rf "${BROWSER_PROFILE_DIR}"

echo "Stopping RTSP publisher..."
if [[ -f "${RTSP_PID_FILE}" ]]; then
  pid="$(cat "${RTSP_PID_FILE}")"
  if [[ -n "${pid}" ]]; then
    # The publisher runs in its own process group (setsid), so a negative PID
    # terminates it together with every ffmpeg child it started.
    kill -TERM "-${pid}" 2>/dev/null || kill -TERM "${pid}" 2>/dev/null || true
  fi
  rm -f "${RTSP_PID_FILE}"
fi
# Fallback in case the process group was already detached: match only the
# ffmpeg publishers started for this demo's RTSP endpoints.
pkill -f "setup_proxy_rtsp.sh -c ${RTSP_CONFIG}" 2>/dev/null || true
if [[ -f "${RTSP_CONFIG}" ]] && command -v jq >/dev/null 2>&1; then
  while IFS= read -r url; do
    [[ -n "${url}" ]] && pkill -f "ffmpeg .*${url}" 2>/dev/null
  done < <(jq -r '.outputs[]?' "${RTSP_CONFIG}" 2>/dev/null)
fi
rm -f "${RTSP_CONFIG}"
docker rm -f "${RTSP_CONTAINER}" >/dev/null 2>&1 || true

echo "Stopping live-video-captioning containers..."
if [[ -f "${APP_DIR}/compose.yaml" && -f "${APP_DIR}/.env" && -f "${DEMO_ENV}" ]]; then
  docker compose -f "${APP_DIR}/compose.yaml" \
    --env-file "${APP_DIR}/.env" \
    --env-file "${DEMO_ENV}" \
    down --remove-orphans 2>/dev/null || true
elif [[ -f "${APP_DIR}/compose.yaml" ]]; then
  docker compose -f "${APP_DIR}/compose.yaml" down --remove-orphans 2>/dev/null || true
fi
