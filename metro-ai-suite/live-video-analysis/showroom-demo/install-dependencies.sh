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

# H.264 codec support for Firefox (required for WebRTC video playback)
sudo apt install -y ffmpeg

echo ""
echo "Done. If Firefox still cannot play H.264 video, open about:config and verify:"
echo "  media.gmp-gmpopenh264.enabled = true"
echo "  media.peerconnection.video.h264_enabled = true"

