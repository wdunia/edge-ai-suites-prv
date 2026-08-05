#!/bin/bash
set -e

sudo apt update

# GStreamer, V4L2 and Python GObject bindings for camera-rtsp.py
sudo apt install -y \
	python3-gi \
	python3-gi-cairo \
	gir1.2-gtk-3.0 \
	gir1.2-gst-plugins-base-1.0 \
	gir1.2-gst-rtsp-server-1.0 \
	gstreamer1.0-plugins-base \
	gstreamer1.0-plugins-good \
	gstreamer1.0-plugins-bad \
	gstreamer1.0-plugins-ugly \
	gstreamer1.0-libav \
	gstreamer1.0-tools \
	v4l-utils

# jq: used by run-pipelines.sh and by the application's setup_proxy_rtsp.sh
sudo apt install -y jq curl

# H.264 codec support for Firefox (required for WebRTC video playback)
# ffmpeg also publishes the looped RTSP demo streams.
sudo apt install -y ffmpeg

# Docker Engine (skipped if already installed)
if ! command -v docker &> /dev/null; then
	echo "Installing Docker..."
	sudo apt install -y ca-certificates curl
	sudo install -m 0755 -d /etc/apt/keyrings
	curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo tee /etc/apt/keyrings/docker.asc > /dev/null
	sudo chmod a+r /etc/apt/keyrings/docker.asc
	echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
		sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
	sudo apt update
	sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
	sudo systemctl enable --now docker
else
	echo "Docker already installed, skipping."
	# Ensure compose plugin is present
	sudo apt install -y docker-compose-plugin 2>/dev/null || true
fi

# Add current user to docker group (avoids needing sudo for docker commands)
if ! groups "$USER" | grep -q '\bdocker\b'; then
	sudo usermod -aG docker "$USER"
	echo "Added $USER to docker group. Log out and back in for it to take effect."
fi

echo ""
echo "Done. If Firefox still cannot play H.264 video, open about:config and verify:"
echo "  media.gmp-gmpopenh264.enabled = true"
echo "  media.peerconnection.video.h264_enabled = true"

