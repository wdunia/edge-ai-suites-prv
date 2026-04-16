#!/usr/bin/env python3
"""RTSP server that streams USB cameras with JPEG frame validation.

Incomplete JPEG frames (common with USB cameras due to bandwidth limits)
are detected via a lightweight GStreamer pad probe that checks only the
last 2 bytes of each buffer for the JPEG EOI marker (0xFFD9).
Invalid frames are dropped at zero-copy cost — the buffer never leaves
GStreamer's pipeline memory.
"""

import gi
gi.require_version('Gst', '1.0')
gi.require_version('GstRtspServer', '1.0')
from gi.repository import Gst, GstRtspServer, GLib

Gst.init(None)

JPEG_EOI = bytes([0xFF, 0xD9])


def _make_probe_callback(device):
    """Return a pad-probe callback that drops incomplete JPEG buffers."""
    stats = {'total': 0, 'dropped': 0}

    def _probe(pad, info):
        buf = info.get_buffer()
        if buf is None or buf.get_size() < 2:
            return Gst.PadProbeReturn.DROP

        stats['total'] += 1

        # Read only the last 2 bytes — no full-buffer copy
        tail = buf.extract_dup(buf.get_size() - 2, 2)
        if tail != JPEG_EOI:
            stats['dropped'] += 1
            if stats['dropped'] % 100 == 1:
                pct = stats['dropped'] / stats['total'] * 100
                print(f"[{device}] dropped {stats['dropped']}/{stats['total']}"
                      f" incomplete frames ({pct:.1f}%)")
            return Gst.PadProbeReturn.DROP

        return Gst.PadProbeReturn.OK

    return _probe


class CameraFactory(GstRtspServer.RTSPMediaFactory):
    def __init__(self, device, width=1280, height=720, framerate=15):
        super().__init__()
        self._device = device
        self.set_launch(
            f"( v4l2src device={device} do-timestamp=true ! "
            f"image/jpeg,width={width},height={height},framerate={framerate}/1 ! "
            f"identity name=probe_{device.replace('/', '_')} ! "
            "jpegdec max-errors=-1 ! "
            "videoconvert ! "
            f"videorate drop-only=true ! video/x-raw,framerate={framerate}/1 ! "
            "x264enc tune=zerolatency bitrate=2000 speed-preset=superfast "
            "key-int-max=30 bframes=0 ! "
            "rtph264pay config-interval=1 name=pay0 pt=96 )"
        )
        self.set_shared(True)

    def do_create_element(self, url):
        element = super().do_create_element(url)
        ident_name = f"probe_{self._device.replace('/', '_')}"
        identity = element.get_by_name(ident_name)
        if identity:
            srcpad = identity.get_static_pad("src")
            srcpad.add_probe(
                Gst.PadProbeType.BUFFER, _make_probe_callback(self._device)
            )
        return element


server = GstRtspServer.RTSPServer()
server.set_service("8555")
mounts = server.get_mount_points()
mounts.add_factory("/c1", CameraFactory('/dev/video0'))
mounts.add_factory("/c2", CameraFactory('/dev/video2'))
server.attach(None)

print("RTSP server running:")
print("rtsp://localhost:8555/c1")
print("rtsp://localhost:8555/c2")
print("Alternative access in Docker network: rtsp://host.docker.internal:8555/c1")
print("Alternative access in Docker network: rtsp://host.docker.internal:8555/c2")

loop = GLib.MainLoop()
try:
    loop.run()
except KeyboardInterrupt:
    print("\nStopping")
    loop.quit()
