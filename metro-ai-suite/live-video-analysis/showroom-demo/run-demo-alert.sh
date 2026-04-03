#!/bin/bash
set -e

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
BASE_DIR=$(cd "$SCRIPT_DIR/../live-video-alert-agent" && pwd)

export REGISTRY="${REGISTRY:-intel/}"
export TAG="${TAG:-1.0.0}"
export TARGET_DEVICE="${TARGET_DEVICE:-GPU}"
export RTSP_URL="${RTSP_URL:-rtsp://localhost:8555/c1}"

APP_URL="http://localhost:9000"

cleanup() {
  echo "Stopping containers..."
  docker compose -f "$BASE_DIR/docker-compose.yml" down
  exit 0
}

trap cleanup SIGINT SIGTERM

bash "$SCRIPT_DIR/stop-all-demos.sh"

echo "Starting live-video-alert-agent..."
docker compose -f "$BASE_DIR/docker-compose.yml" up -d

echo "App URL: $APP_URL"
sleep 3
xdg-open "$APP_URL" &

cd "$SCRIPT_DIR"
python3 camera-rtsp.py
