#!/usr/bin/env python3
"""RTSP server that streams USB cameras over H.264."""

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


server = GstRtspServer.RTSPServer()
server.set_service("8555")
mounts = server.get_mount_points()
mounts.add_factory("/c1", CameraFactory('/dev/video0'))
mounts.add_factory("/c2", CameraFactory('/dev/video2'))
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
