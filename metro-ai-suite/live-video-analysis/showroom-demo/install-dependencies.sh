#!/bin/bash
sudo apt update
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
