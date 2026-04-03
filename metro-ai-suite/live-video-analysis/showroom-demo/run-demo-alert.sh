#!/bin/bash
set -e

export REGISTRY="intel/"
export TAG="1.0.0"
export TARGET_DEVICE=GPU
export RTSP_URL="rtsp://localhost:8555/c1"

BASE_DIR=../live-video-alert-agent

cleanup() {
  echo "Stopping containers..."
  cd "$BASE_DIR"
  docker compose down
  exit 0
}

trap cleanup SIGINT SIGTERM

cd "$BASE_DIR"
docker ps -aq | xargs -r docker stop
docker ps -aq | xargs -r docker rm
docker compose up -d

echo "App URL: http://localhost:9000"

cd ~/demo
sleep 3
xdg-open http://localhost:9000
python3 camera-rtsp.py
