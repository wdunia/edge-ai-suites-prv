#!/usr/bin/env python3
# Copyright (C) 2026 Intel Corporation
# SPDX-License-Identifier: Apache-2.0

"""
RTSP Stream Simulator.

Streams a USB camera or local MP4 files over RTSP for use as a video source in edge AI applications.

Usage:
    # Stream USB camera (default /dev/video0):
    python3 rtsp_server.py --camera /dev/video0

    # Stream a local MP4 file:
    python3 rtsp_server.py --file /path/to/video.mp4

    # Stream all MP4 files from a directory:
    python3 rtsp_server.py --dir /path/to/videos/

    # Custom port:
    python3 rtsp_server.py --file video.mp4 --port 8554

Requirements:
    sudo apt-get install -y gstreamer1.0-rtsp libgstrtspserver-1.0-0 \
        gstreamer1.0-plugins-ugly gstreamer1.0-plugins-bad \
        gstreamer1.0-plugins-good gstreamer1.0-plugins-base \
        python3-gst-1.0 gir1.2-gstrtspserver-1.0

Notes:
    - MP4 files must contain H.264-encoded video.
    - USB camera pipeline assumes the camera supports MJPEG output.
      If your camera only supports raw (YUV), change the pipeline caps
      or use a camera that advertises image/jpeg.
    - The EOS-based loop seeks back to the beginning when the file ends.
      For very short files (<5s), consider concatenating them first with
      ffmpeg for more reliable looping.
"""

import argparse
import glob
import os
import sys

import gi

gi.require_version("Gst", "1.0")
gi.require_version("GstRtspServer", "1.0")
from gi.repository import GLib, Gst, GstRtspServer  # noqa: E402

Gst.init(None)

DEFAULT_PORT = "8554"
DEFAULT_WIDTH = 1280
DEFAULT_HEIGHT = 720
DEFAULT_FRAMERATE = 30


def create_camera_factory(
    device: str, width: int, height: int, framerate: int
) -> GstRtspServer.RTSPMediaFactory:
    """Create an RTSP media factory for a USB camera (V4L2 + H.264 encode).

    The pipeline captures MJPEG from the camera, decodes it, and re-encodes
    to H.264 with low-latency settings suitable for real-time streaming.
    """
    factory = GstRtspServer.RTSPMediaFactory()
    factory.set_launch(
        f"( v4l2src device={device} do-timestamp=true ! "
        f"image/jpeg,width={width},height={height},framerate={framerate}/1 ! "
        "jpegdec ! videoconvert ! "
        "x264enc tune=zerolatency bitrate=2000 speed-preset=superfast ! "
        "rtph264pay config-interval=1 name=pay0 pt=96 )"
    )
    factory.set_shared(True)
    return factory


def create_file_factory(filepath: str) -> GstRtspServer.RTSPMediaFactory:
    """Create an RTSP media factory for an H.264 MP4 file with looping.

    The pipeline performs H.264 passthrough (no re-encoding) and seeks
    back to the start on EOS to provide continuous playback.
    """
    factory = GstRtspServer.RTSPMediaFactory()
    factory.set_launch(
        f"( filesrc location={filepath} ! qtdemux ! h264parse config-interval=1 ! "
        "rtph264pay name=pay0 pt=96 )"
    )
    factory.set_shared(True)

    def _on_media_configure(_factory, media):
        """Attach an EOS handler that seeks to the beginning for looping."""

        def _on_eos(_bus, _msg):
            element = media.get_element()
            element.seek_simple(
                Gst.Format.TIME,
                Gst.SeekFlags.FLUSH | Gst.SeekFlags.KEY_UNIT,
                0,
            )

        element = media.get_element()
        bus = element.get_bus()
        bus.add_signal_watch()
        bus.connect("message::eos", _on_eos)

    factory.connect("media-configure", _on_media_configure)
    return factory


def parse_args() -> argparse.Namespace:
    """Parse command-line arguments."""
    parser = argparse.ArgumentParser(
        description="Simulate RTSP streams from USB cameras or local video files.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=(
            "Examples:\n"
            "  %(prog)s --camera /dev/video0\n"
            "  %(prog)s --file sample.mp4\n"
            "  %(prog)s --dir ./videos --port 8555\n"
        ),
    )
    parser.add_argument(
        "--camera",
        metavar="DEVICE",
        help="V4L2 camera device path (e.g., /dev/video0)",
    )
    parser.add_argument(
        "--file",
        metavar="PATH",
        action="append",
        default=[],
        help="path to an H.264 MP4 file to stream (repeatable)",
    )
    parser.add_argument(
        "--dir",
        metavar="DIR",
        help="directory containing MP4 files to stream",
    )
    parser.add_argument(
        "--port",
        default=DEFAULT_PORT,
        help=f"RTSP server port (default: {DEFAULT_PORT})",
    )
    parser.add_argument(
        "--width", type=int, default=DEFAULT_WIDTH, help="camera capture width"
    )
    parser.add_argument(
        "--height", type=int, default=DEFAULT_HEIGHT, help="camera capture height"
    )
    parser.add_argument(
        "--framerate", type=int, default=DEFAULT_FRAMERATE, help="camera framerate"
    )
    return parser.parse_args()


def main() -> None:
    """Entry point: configure and start the RTSP server."""
    args = parse_args()

    if not args.camera and not args.file and not args.dir:
        print(
            "ERROR: Specify at least one of --camera, --file, or --dir.",
            file=sys.stderr,
        )
        sys.exit(1)

    server = GstRtspServer.RTSPServer()
    server.set_service(args.port)
    mounts = server.get_mount_points()

    endpoints: list[tuple[str, str]] = []

    # Mount camera stream
    if args.camera:
        factory = create_camera_factory(
            args.camera, args.width, args.height, args.framerate
        )
        mounts.add_factory("/camera", factory)
        endpoints.append(("/camera", f"USB camera ({args.camera})"))

    # Collect MP4 files
    mp4_files = list(args.file)
    if args.dir:
        mp4_files.extend(sorted(glob.glob(os.path.join(args.dir, "*.mp4"))))

    # Mount file streams
    for i, filepath in enumerate(mp4_files, start=1):
        if not os.path.isfile(filepath):
            print(f"WARNING: File not found, skipping: {filepath}", file=sys.stderr)
            continue
        endpoint = f"/video{i}"
        mounts.add_factory(endpoint, create_file_factory(os.path.abspath(filepath)))
        endpoints.append((endpoint, os.path.basename(filepath)))

    if not endpoints:
        print("ERROR: No valid streams to serve.", file=sys.stderr)
        sys.exit(1)

    server.attach(None)

    print(f"RTSP server running on port {args.port}:\n")
    for endpoint, description in endpoints:
        print(f"  rtsp://localhost:{args.port}{endpoint}  — {description}")
    print("\nFrom Docker containers, use:")
    for endpoint, _ in endpoints:
        print(f"  rtsp://host.docker.internal:{args.port}{endpoint}")
    print()

    loop = GLib.MainLoop()
    try:
        loop.run()
    except KeyboardInterrupt:
        print("\nStopping RTSP server.")
        loop.quit()


if __name__ == "__main__":
    main()
