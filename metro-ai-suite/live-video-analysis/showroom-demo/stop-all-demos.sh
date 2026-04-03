#!/bin/bash
# Stops all known demo stacks. Called automatically by run-demo-*.sh before starting a new demo.
# To add a new demo, add its directory name to the DEMO_DIRS list below.

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)

DEMO_DIRS=(
  live-video-alert-agent
  live-video-captioning
)

echo "Stopping any running demo containers..."
for dir in "${DEMO_DIRS[@]}"; do
  compose_file="$SCRIPT_DIR/../$dir/docker-compose.yml"
  if [ -f "$compose_file" ]; then
    docker compose -f "$compose_file" down --remove-orphans 2>/dev/null || true
  fi
done

