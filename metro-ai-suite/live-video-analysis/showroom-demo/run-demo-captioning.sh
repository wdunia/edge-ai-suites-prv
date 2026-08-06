#!/usr/bin/env bash
# SPDX-FileCopyrightText: (C) 2026 Intel Corporation
# SPDX-License-Identifier: Apache-2.0
#
# Showroom demo launcher for live-video-captioning.
# Follows the documented application flow:
#   scripts/setup_env.sh --force -> model download (GPU) -> docker compose up
# and then starts the demo pipelines defined in pipelines.json.
#
# Press Ctrl+C to stop the demo; all containers and RTSP streams are cleaned up.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_DIR="$(cd "${SCRIPT_DIR}/../live-video-captioning" && pwd)"
DEMO_ENV="${SCRIPT_DIR}/captioning-demo.env"

VLM_MODEL="${VLM_MODEL:-OpenGVLab/InternVL2-1B}"
VLM_DEVICE="GPU"
WEIGHT_FORMAT="${WEIGHT_FORMAT:-int8}"

log()  { echo "[demo] $*"; }
die()  { echo "[demo] ERROR: $*" >&2; exit 1; }

compose() {
  docker compose -f "${APP_DIR}/compose.yaml" \
    --env-file "${APP_DIR}/.env" \
    --env-file "${DEMO_ENV}" "$@"
}

cleanup() {
  trap - EXIT INT TERM
  echo
  log "Stopping demo..."
  bash "${SCRIPT_DIR}/stop-all-demos.sh" || true
  exit 0
}
trap cleanup INT TERM EXIT

command -v docker >/dev/null 2>&1 || die "Docker is required. Run ./install-dependencies.sh first."
command -v jq >/dev/null 2>&1 || die "jq is required. Run ./install-dependencies.sh first."
[[ -f "${DEMO_ENV}" ]] || die "Missing demo overrides: ${DEMO_ENV}"

# 1. Stop whatever is still running from a previous demo session.
bash "${SCRIPT_DIR}/stop-all-demos.sh"

# 2. Regenerate .env so HOST_IP always matches the current network.
log "Regenerating ${APP_DIR}/.env"
bash "${APP_DIR}/scripts/setup_env.sh" --force

# setup_env.sh derives HOST_IP from the default route, which is not the Wi-Fi
# access point address on the showroom machine. Allow the caller (the desktop
# launcher and StartPreview.ps1 both pass HOST_IP=192.168.100.1) to pin it, so
# WebRTC and the RTSP streams stay reachable from the client laptop.
if [[ -n "${HOST_IP:-}" ]]; then
  sed -i "s|^HOST_IP=.*|HOST_IP=${HOST_IP}|" "${APP_DIR}/.env"
  log "Pinned HOST_IP=${HOST_IP} from the environment"
fi

# --force resets .env to the template, so re-apply the Hugging Face token from
# the environment (needed for gated models). Never store it in a tracked file.
if [[ -n "${HUGGINGFACEHUB_API_TOKEN:-}" ]]; then
  sed -i "s|^HUGGINGFACEHUB_API_TOKEN=.*|HUGGINGFACEHUB_API_TOKEN=${HUGGINGFACEHUB_API_TOKEN}|" "${APP_DIR}/.env"
  log "Applied HUGGINGFACEHUB_API_TOKEN from the environment"
fi

HOST_IP="$(grep -E '^HOST_IP=' "${APP_DIR}/.env" | tail -1 | cut -d= -f2-)"
HOST_IP="${HOST_IP:-127.0.0.1}"
DASHBOARD_PORT="$(grep -E '^DASHBOARD_PORT=' "${APP_DIR}/.env" | tail -1 | cut -d= -f2-)"
DASHBOARD_PORT="${DASHBOARD_PORT:-4173}"

# The RTSP streams are served from the host IP. Behind a corporate proxy the
# pipeline server must bypass the proxy for it, otherwise the stream stalls and
# DLSPS can crash (see the application's known-issues guide).
NO_PROXY_BASE="localhost,127.0.0.1,${HOST_IP},host.docker.internal"
export no_proxy="${NO_PROXY_BASE}${no_proxy:+,${no_proxy}}"
export NO_PROXY="${NO_PROXY_BASE}${NO_PROXY:+,${NO_PROXY}}"
log "no_proxy=${no_proxy}"

# 3. Download and convert the VLM once (quick-start step 3, with --device GPU).
#    The guard keeps the "one-time" behaviour across demo restarts.
MODEL_DIR="${APP_DIR}/ov_models/$(echo "${VLM_DEVICE}" | tr '[:upper:]' '[:lower:]')/${VLM_MODEL##*/}"
if [[ -d "${MODEL_DIR}" ]]; then
  log "VLM already available: ${MODEL_DIR}"
else
  log "Downloading and converting ${VLM_MODEL} for ${VLM_DEVICE} (one-time, several minutes)..."
  bash "${APP_DIR}/model_download_scripts/download_models.sh" \
    --model "${VLM_MODEL}" \
    --type vlm \
    --weight-format "${WEIGHT_FORMAT}" \
    --device "${VLM_DEVICE}"
fi

# 4. Start the application stack with the showroom overrides.
log "Starting live-video-captioning..."
compose up -d

# 5. Start the demo pipelines (USB camera + video files) before opening the UI.
bash "${SCRIPT_DIR}/run-pipelines.sh"

# 6. Open the dashboard in a clean browser window.
#    A throwaway profile directory is used so the demo never restores tabs,
#    sessions or bookmarks from a previous run. The window is a normal one:
#    full-screen/kiosk mode showed a black window on this machine, so the
#    operator can simply press F11 if a full-screen view is wanted.
APP_URL="http://${HOST_IP}:${DASHBOARD_PORT}"
log "Dashboard: ${APP_URL}"

BROWSER_PID_FILE="${SCRIPT_DIR}/.browser.pid"
BROWSER_PROFILE_DIR="${SCRIPT_DIR}/.browser-profile"

open_dashboard() {
  # Always start from an empty profile: no restored tabs, no session prompt.
  rm -rf "${BROWSER_PROFILE_DIR}"
  mkdir -p "${BROWSER_PROFILE_DIR}"

  # A fresh profile otherwise triggers the keyring unlock dialog and the
  # first-run/session-restore prompts, which cover the dashboard.
  local common_args=(
    --user-data-dir="${BROWSER_PROFILE_DIR}"
    --new-window
    --no-first-run
    --no-default-browser-check
    --disable-session-crashed-bubble
    --disable-infobars
    --password-store=basic
    --use-mock-keychain
  )

  local browser
  for browser in google-chrome google-chrome-stable chromium chromium-browser microsoft-edge microsoft-edge-stable; do
    if command -v "${browser}" >/dev/null 2>&1; then
      setsid "${browser}" "${common_args[@]}" "${APP_URL}" >/dev/null 2>&1 &
      echo $! > "${BROWSER_PID_FILE}"
      log "Opened ${browser} with a clean profile (press F11 for full screen)"
      return 0
    fi
  done

  if command -v firefox >/dev/null 2>&1; then
    setsid firefox --profile "${BROWSER_PROFILE_DIR}" --no-remote --new-window \
      "${APP_URL}" >/dev/null 2>&1 &
    echo $! > "${BROWSER_PID_FILE}"
    log "Opened firefox with a clean profile (press F11 for full screen)"
    return 0
  fi

  if command -v xdg-open >/dev/null 2>&1; then
    log "No Chromium/Firefox found; falling back to xdg-open (press F11 for full screen)"
    xdg-open "${APP_URL}" >/dev/null 2>&1 &
  fi
}

open_dashboard

log "Demo is running. Press Ctrl+C to stop."
while true; do
  sleep 3600
done

