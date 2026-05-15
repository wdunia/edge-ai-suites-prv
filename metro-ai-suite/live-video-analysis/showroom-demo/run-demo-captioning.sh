#!/bin/bash
set -e

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
BASE_DIR=$(cd "$SCRIPT_DIR/../live-video-captioning" && pwd)

export REGISTRY="${REGISTRY:-intel/}"
export TAG="${TAG:-latest}"
export TARGET_DEVICE="${TARGET_DEVICE:-GPU}"
export RTSP_URL="${RTSP_URL:-rtsp://host.docker.internal:8555/c1}"

# live-video-captioning .env variables
export HOST_IP="${HOST_IP:-127.0.0.1}"
export WHIP_SERVER_PORT="${WHIP_SERVER_PORT:-8889}"
export WHIP_SERVER_TIMEOUT="${WHIP_SERVER_TIMEOUT:-60s}"
export PROJECT_NAME="${PROJECT_NAME:-live-captioning}"
export EVAM_HOST_PORT="${EVAM_HOST_PORT:-8040}"
export EVAM_PORT="${EVAM_PORT:-8080}"
export DASHBOARD_PORT="${DASHBOARD_PORT:-4173}"
export WEBRTC_PEER_ID="${WEBRTC_PEER_ID:-stream}"
export ALERT_MODE="True"
export CAPTION_HISTORY="${CAPTION_HISTORY:-3}"
export ENABLE_DETECTION_PIPELINE="${ENABLE_DETECTION_PIPELINE:-"True"}"
export DEFAULT_RTSP_URL="${DEFAULT_RTSP_URL:-rtsp://host.docker.internal:8555/c1}"

APP_URL="http://localhost:4173"

cleanup() {
  echo "Stopping containers..."
  docker compose -f "$BASE_DIR/compose.yaml" down
  exit 0
}

trap cleanup SIGINT SIGTERM

bash "$SCRIPT_DIR/stop-all-demos.sh"

echo "Starting live-video-captioning..."
docker compose -f "$BASE_DIR/compose.yaml" up -d

echo "App URL: $APP_URL"
sleep 3
xdg-open "$APP_URL" &

cd "$SCRIPT_DIR"
#python3 camera-rtsp.py ./videos

exit
