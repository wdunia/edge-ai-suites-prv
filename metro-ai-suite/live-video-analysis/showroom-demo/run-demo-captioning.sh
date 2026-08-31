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
PIPELINES_FILE="${SCRIPT_DIR}/pipelines.json"

VLM_MODEL="${VLM_MODEL:-OpenGVLab/InternVL2-1B}"
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
[[ -f "${PIPELINES_FILE}" ]] || die "Missing pipeline configuration: ${PIPELINES_FILE}"

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

# 3. Download and convert the VLM once (quick-start step 3) for every device the
#    demo runs on. The guard keeps the "one-time" behaviour across demo restarts.
VLM_DEVICES=()
while IFS= read -r device; do
  VLM_DEVICES+=("${device}")
done < <(jq -r '[(.vlmDevice // "gpu")] + [.runs[].vlmDevice // empty] | map(ascii_upcase) | unique | .[]' "${PIPELINES_FILE}")
[[ ${#VLM_DEVICES[@]} -gt 0 ]] || VLM_DEVICES=("GPU")

for device in "${VLM_DEVICES[@]}"; do
  MODEL_DIR="${APP_DIR}/ov_models/$(echo "${device}" | tr '[:upper:]' '[:lower:]')/${VLM_MODEL##*/}"
  if [[ -d "${MODEL_DIR}" ]]; then
    log "VLM already available for ${device}: ${MODEL_DIR}"
  else
    log "Downloading and converting ${VLM_MODEL} for ${device} (one-time, several minutes)..."
    bash "${APP_DIR}/model_download_scripts/download_models.sh" \
      --model "${VLM_MODEL}" \
      --type vlm \
      --weight-format "${WEIGHT_FORMAT}" \
      --device "${device}"
  fi
done

# 4. Start the application stack with the showroom overrides.
log "Starting live-video-captioning..."
compose up -d

# 5. Start the demo pipelines (USB camera + video files) before opening the UI.
bash "${SCRIPT_DIR}/run-pipelines.sh"

# 6. Open the dashboard in a clean, maximized browser window.
#    A throwaway profile directory is used so the demo never restores tabs,
#    sessions or bookmarks from a previous run. The window is maximized (not
#    full screen/kiosk - that rendered a black window on this machine), so the
#    dashboard fills the whole screen.
APP_URL="http://${HOST_IP}:${DASHBOARD_PORT}"
log "Dashboard: ${APP_URL}"

BROWSER_PID_FILE="${SCRIPT_DIR}/.browser.pid"
BROWSER_PROFILE_DIR="${SCRIPT_DIR}/.browser-profile"

# Screen geometry (WIDTHxHEIGHT) of the primary monitor, used to size the
# browser window.
screen_size() {
  local geom=""
  if command -v xrandr >/dev/null 2>&1; then
    geom="$(xrandr 2>/dev/null | awk '/\*/ {print $1; exit}')"
  fi
  if [[ -z "${geom}" ]] && command -v xdpyinfo >/dev/null 2>&1; then
    geom="$(xdpyinfo 2>/dev/null | awk '/dimensions:/ {print $2; exit}')"
  fi
  echo "${geom}"
}

# Firefox has no command line option for the window size: it restores the window
# geometry from xulstore.json inside the profile. Because the demo starts from an
# empty profile every time, Firefox would fall back to its small default window,
# so the profile is seeded with a maximized main window before it is started.
seed_firefox_profile() {
  local geom width height
  geom="$(screen_size)"
  if [[ "${geom}" =~ ^([0-9]+)x([0-9]+)$ ]]; then
    width="${BASH_REMATCH[1]}"
    height="${BASH_REMATCH[2]}"
  else
    width=1920
    height=1080
  fi

  cat > "${BROWSER_PROFILE_DIR}/xulstore.json" <<EOF
{"chrome://browser/content/browser.xhtml":{"main-window":{"screenX":"0","screenY":"0","width":"${width}","height":"${height}","sizemode":"maximized"}}}
EOF

  # Skip the "welcome"/"what's new" tabs a brand new profile would open on top
  # of the dashboard.
  cat > "${BROWSER_PROFILE_DIR}/user.js" <<'EOF'
user_pref("browser.startup.homepage_override.mstone", "ignore");
user_pref("browser.aboutwelcome.enabled", false);
user_pref("datareporting.policy.firstRunURL", "");
user_pref("browser.shell.checkDefaultBrowser", false);
user_pref("browser.sessionstore.resume_from_crash", false);
EOF
}

open_dashboard() {
  log "Desktop session: ${XDG_SESSION_TYPE:-unknown} (DISPLAY=${DISPLAY:-none}, screen=$(screen_size))"

  # Always start from an empty profile: no restored tabs, no session prompt.
  rm -rf "${BROWSER_PROFILE_DIR}"
  mkdir -p "${BROWSER_PROFILE_DIR}"

  # A fresh profile otherwise triggers the keyring unlock dialog and the
  # first-run/session-restore prompts, which cover the dashboard.
  local common_args=(
    --user-data-dir="${BROWSER_PROFILE_DIR}"
    --new-window
    --start-maximized
    --window-position=0,0
    --no-first-run
    --no-default-browser-check
    --disable-session-crashed-bubble
    --disable-infobars
    --password-store=basic
    --use-mock-keychain
  )

  # Explicit window size for window managers that ignore --start-maximized.
  local geom
  geom="$(screen_size)"
  if [[ "${geom}" =~ ^([0-9]+)x([0-9]+)$ ]]; then
    common_args+=(--window-size="${BASH_REMATCH[1]},${BASH_REMATCH[2]}")
  fi

  local browser
  for browser in google-chrome google-chrome-stable chromium chromium-browser microsoft-edge microsoft-edge-stable; do
    if command -v "${browser}" >/dev/null 2>&1; then
      setsid "${browser}" "${common_args[@]}" "${APP_URL}" >/dev/null 2>&1 &
      echo $! > "${BROWSER_PID_FILE}"
      log "Opened ${browser} maximized with a clean profile"
      return 0
    fi
  done

  if command -v firefox >/dev/null 2>&1; then
    # Firefox ignores window-size command line options; the geometry comes from
    # the profile, so it is prepared first.
    seed_firefox_profile
    setsid firefox --profile "${BROWSER_PROFILE_DIR}" --no-remote --new-window \
      "${APP_URL}" >/dev/null 2>&1 &
    echo $! > "${BROWSER_PID_FILE}"
    log "Opened firefox maximized with a clean profile"
    return 0
  fi

  if command -v xdg-open >/dev/null 2>&1; then
    log "No Chromium/Firefox found; falling back to xdg-open"
    xdg-open "${APP_URL}" >/dev/null 2>&1 &
  fi
}

open_dashboard

log "Demo is running. Press Ctrl+C to stop."
while true; do
  sleep 3600
done
