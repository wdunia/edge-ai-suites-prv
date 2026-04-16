#!/usr/bin/env python3
"""RTSP server that streams USB cameras over H.264.

Uses raw YUYV capture (instead of MJPEG) to completely eliminate
incomplete-frame artifacts (gray bars, blinking). Raw capture is
artifact-free because every frame has a fixed size — there is no
compression that can produce partial data.

For higher resolutions where USB bandwidth is insufficient for raw
capture, set use_mjpeg=True to fall back to MJPEG.
"""

import gi
gi.require_version('Gst', '1.0')
gi.require_version('GstRtspServer', '1.0')
from gi.repository import Gst, GstRtspServer, GLib

Gst.init(None)


class CameraFactory(GstRtspServer.RTSPMediaFactory):
    def __init__(self, device, width=640, height=480, framerate=15,
                 use_mjpeg=False):
        super().__init__()
        if use_mjpeg:
            source = (
                f"v4l2src device={device} do-timestamp=true ! "
                f"image/jpeg,width={width},height={height},"
                f"framerate={framerate}/1 ! "
                "queue max-size-buffers=3 leaky=downstream ! "
                "jpegdec ! "
                "queue max-size-buffers=3 leaky=downstream ! "
                "videoconvert"
            )
        else:
            source = (
                f"v4l2src device={device} do-timestamp=true ! "
                f"video/x-raw,format=YUY2,width={width},height={height},"
                f"framerate={framerate}/1 ! "
                "queue max-size-buffers=3 leaky=downstream ! "
                "videoconvert"
            )
        self.set_launch(
            f"( {source} ! "
            f"videorate drop-only=true ! video/x-raw,framerate={framerate}/1 ! "
            "x264enc tune=zerolatency bitrate=2000 speed-preset=superfast "
            "key-int-max=30 bframes=0 ! "
            "rtph264pay config-interval=1 name=pay0 pt=96 )"
        )
        self.set_shared(True)


server = GstRtspServer.RTSPServer()
server.set_service("8555")
mounts = server.get_mount_points()

# Raw YUYV at 640x480 — zero artifacts, works on USB 2.0
# For 1280x720 on USB 2.0, use: use_mjpeg=True
mounts.add_factory("/c1", CameraFactory('/dev/video0', 640, 480, 15))
mounts.add_factory("/c2", CameraFactory('/dev/video2', 640, 480, 15))

server.attach(None)

print("RTSP server running:")
print("  rtsp://localhost:8555/c1  (Docker: rtsp://host.docker.internal:8555/c1)")
print("  rtsp://localhost:8555/c2  (Docker: rtsp://host.docker.internal:8555/c2)")

loop = GLib.MainLoop()
try:
    loop.run()
except KeyboardInterrupt:
    print("\nStopping")
    loop.quit()
