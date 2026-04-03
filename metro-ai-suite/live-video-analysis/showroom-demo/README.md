# Showroom Demo — Live Video Analysis

Two demo applications that analyse a live USB camera feed using AI:

| Demo | What it does | URL |
|------|-------------|-----|
| **live-video-alert-agent** | Detects events in the video stream and raises alerts | http://localhost:9000 |
| **live-video-captioning** | Generates real-time natural-language captions of the scene | http://localhost:4173 |

Each demo runs as a set of Docker containers. A local RTSP server (`camera-rtsp.py`) streams
the USB camera feed into the pipeline.

---

## First-time setup

> Skip this section if you have already run a demo on this machine before.

**1. Install system dependencies** (GStreamer, V4L2, Python GObject bindings):

```bash
./install-dependencies.sh
```

**2. Connect a USB camera** — a Logitech C920 Pro or any UVC-compliant webcam.
Plug it in, then verify it is detected:

```bash
ls /dev/video*        # expect /dev/video0 (and /dev/video2 for a second camera)
./list-camera-formats.sh   # confirm MJPEG 1280x720 @ 15 fps is listed
```

If the device node is not `/dev/video0`, update the two `CameraFactory` lines at the bottom
of `camera-rtsp.py` to match.

---

## Running a demo

```bash
./run-demo-alert.sh       # launch the alert-agent demo
# or
./run-demo-captioning.sh  # launch the captioning demo
```

The script will:
1. Stop any other running demo automatically.
2. Start the Docker containers for the selected application.
3. Open the app UI in the browser.
4. Start streaming the camera over RTSP.

Press **Ctrl+C** at any time to stop — containers are shut down automatically.

### Overriding defaults

Environment variables can be passed inline or set before running:

```bash
TARGET_DEVICE=CPU ./run-demo-alert.sh
TAG=1.1.0 ./run-demo-captioning.sh
```

| Variable | Default | Description |
|----------|---------|-------------|
| `TARGET_DEVICE` | `GPU` | Inference device (`GPU` or `CPU`) |
| `TAG` | `1.0.0` | Docker image tag |
| `REGISTRY` | `intel/` | Docker image registry prefix |
| `RTSP_URL` | *(per script)* | RTSP stream URL passed to the containers |

---

## Troubleshooting

| Symptom | Fix |
|---------|-----|
| `No such file or directory: /dev/video0` | Check USB connection; run `dmesg \| tail -20` |
| Video stream is black or missing | Run `./list-camera-formats.sh` and update device paths in `camera-rtsp.py` |
| Browser does not open automatically | Navigate manually to the URL shown in the terminal |
| Docker Compose fails to start | Check that images exist: `docker images \| grep live-video` |

---

## Reference

<details>
<summary>How the RTSP camera server works</summary>

`camera-rtsp.py` captures frames from V4L2 devices and re-encodes them as H.264 over RTP
using GStreamer, making the feed available both to the host and to Docker containers:

- Host: `rtsp://localhost:8555/c1`, `rtsp://localhost:8555/c2`
- Inside Docker: `rtsp://host.docker.internal:8555/c1`, `.../c2`

The C920 Pro outputs native MJPEG, which avoids software decoding before re-encoding
and keeps CPU usage and latency low.

</details>

<details>
<summary>Adding a new demo</summary>

Register the new project's directory name in the `DEMO_DIRS` list in `stop-all-demos.sh`.
No changes to any other script are needed.

</details>



