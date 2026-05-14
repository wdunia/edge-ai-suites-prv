#!/usr/bin/env python3
"""RTSP server that streams USB cameras and local MP4 files over H.264."""

import sys
import glob
import os
import shutil
import subprocess
import gi
gi.require_version('Gst', '1.0')
gi.require_version('GstRtspServer', '1.0')
from gi.repository import Gst, GstRtspServer, GLib

Gst.init(None)


class CameraFactory(GstRtspServer.RTSPMediaFactory):
    def __init__(self, device, width=1280, height=720, framerate=15):
        super().__init__()
        self.set_launch(
            f"( v4l2src device={device} do-timestamp=true ! "
            f"image/jpeg,width={width},height={height},framerate={framerate}/1 ! "
            "rtpjpegpay name=pay0 pt=26 )"
        )
        self.set_shared(True)

class CameraFactory2(GstRtspServer.RTSPMediaFactory):
    def __init__(self, device, width=1280, height=720, framerate=30):
        super().__init__()
        self.set_launch(
            f"( v4l2src device={device} do-timestamp=true ! "
            f"image/jpeg,width={width},height={height},framerate={framerate}/1 ! "
            "jpegdec !"
            "videoconvert ! "
            "x264enc tune=zerolatency bitrate=2000 speed-preset=superfast ! "
            "rtph264pay config-interval=1 name=pay0 pt=96 )"
        )
        self.set_shared(True)


class FileFactory(GstRtspServer.RTSPMediaFactory):
    """Streams a pre-looped MP4 file as H.264 RTSP (passthrough, no re-encode)."""
    def __init__(self, filepath, use_loop=True):
        super().__init__()
        source = self._ensure_looped(filepath) if use_loop else filepath
        self.set_launch(
            f"( filesrc location={source} ! qtdemux ! h264parse config-interval=1 ! "
            "rtph264pay name=pay0 pt=96 )"
        )
        self.set_shared(True)
        self.connect("media-configure", self._on_media_configure)

    @staticmethod
    def _on_media_configure(factory, media):
        """On EOS, seek back to start for infinite loop."""
        def on_eos(bus, msg):
            element = media.get_element()
            element.seek_simple(
                Gst.Format.TIME,
                Gst.SeekFlags.FLUSH | Gst.SeekFlags.KEY_UNIT,
                0
            )
        element = media.get_element()
        bus = element.get_bus()
        bus.add_signal_watch()
        bus.connect("message::eos", on_eos)

    @staticmethod
    def _ensure_looped(filepath, loops=500):
        """Create a looped copy of the file (passthrough, no re-encode)."""
        looped_path = filepath.replace(".mp4", "_looped.mp4")
        if os.path.exists(looped_path):
            return looped_path

        if not shutil.which("ffmpeg"):
            sys.exit("ERROR: ffmpeg not found. Run install-dependencies.sh first.")

        print(f"  Creating looped file: {looped_path} ({loops}x)...")
        result = subprocess.run(
            ["ffmpeg", "-y", "-stream_loop", str(loops - 1), "-i", filepath,
             "-c", "copy", "-an", looped_path],
            capture_output=True, text=True
        )
        if result.returncode != 0:
            print(f"  WARNING: ffmpeg failed, using original: {result.stderr[:200]}")
            return filepath
        print(f"  Done: {looped_path}")
        return looped_path


server = GstRtspServer.RTSPServer()
server.set_service("8555")
mounts = server.get_mount_points()
mounts.add_factory("/c1", CameraFactory2('/dev/video0'))
mounts.add_factory("/c2", CameraFactory2('/dev/video2'))

# Stream local MP4 files from a directory (pass path as first argument)
# Use --no-loop to skip creating looped copies (relies on GStreamer EOS seek only)
use_loop = "--no-loop" not in sys.argv
args = [a for a in sys.argv[1:] if a != "--no-loop"]

file_streams = []
if args:
    video_dir = args[0]
    mp4_files = sorted(f for f in glob.glob(os.path.join(video_dir, "*.mp4")) if not f.endswith("_looped.mp4"))
    for i, filepath in enumerate(mp4_files, start=1):
        endpoint = f"/f{i}"
        mounts.add_factory(endpoint, FileFactory(filepath, use_loop=use_loop))
        file_streams.append((endpoint, filepath))

server.attach(None)

print("RTSP server running:")
print("  rtsp://localhost:8555/c1    (USB camera 1)")
print("  rtsp://localhost:8555/c2    (USB camera 2)")
for endpoint, filepath in file_streams:
    print(f"  rtsp://localhost:8555{endpoint}  ({os.path.basename(filepath)})")
print()
print("  Docker: use rtsp://host.docker.internal:8555/...")
if not file_streams:
    if args:
        print(f"  (No *.mp4 files found in {args[0]})")
    else:
        print("  (No MP4 directory given — pass a path as argument to stream files)")

loop = GLib.MainLoop()
try:
    loop.run()
except KeyboardInterrupt:
    print("\nStopping")
    loop.quit()
