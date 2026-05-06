#!/usr/bin/env python3
"""RTSP server that streams USB cameras and local MP4 files over H.264."""

import sys
import glob
import os
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
    def __init__(self, filepath):
        super().__init__()
        # Use the looped file for hours-long uninterrupted streaming
        looped = self._ensure_looped(filepath)
        self.set_launch(
            f"( filesrc location={looped} ! qtdemux ! h264parse config-interval=1 ! "
            "rtph264pay name=pay0 pt=96 )"
        )
        self.set_shared(True)

    @staticmethod
    def _ensure_looped(filepath, loops=200):
        """Create a looped copy of the file (concat without re-encode) if not already done."""
        looped_path = filepath.replace(".mp4", "_looped.mp4")
        if os.path.exists(looped_path):
            return looped_path
        print(f"  Creating looped file: {looped_path} ({loops}x)...")
        import subprocess
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
file_streams = []
if len(sys.argv) > 1:
    video_dir = sys.argv[1]
    mp4_files = sorted(glob.glob(os.path.join(video_dir, "*.mp4")))
    for i, filepath in enumerate(mp4_files, start=1):
        endpoint = f"/file{i}"
        mounts.add_factory(endpoint, FileFactory(filepath))
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
    if len(sys.argv) > 1:
        print(f"  (No *.mp4 files found in {video_dir})")
    else:
        print("  (No MP4 directory given — pass a path as argument to stream files)")

loop = GLib.MainLoop()
try:
    loop.run()
except KeyboardInterrupt:
    print("\nStopping")
    loop.quit()
