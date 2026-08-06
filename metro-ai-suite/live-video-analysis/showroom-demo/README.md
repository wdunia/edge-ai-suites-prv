# Showroom Demo — Live Video Captioning

One-command showroom demo for the
[live-video-captioning](../live-video-captioning) application: it generates
real-time natural-language captions for four parallel video sources.

| Source | Pipeline |
|--------|----------|
| USB camera (`/dev/video0`) | `Video_Captioning_Camera_Hardware` (GPU) |
| 3 local video files | `Video_Captioning_RTSP_Hardware` (GPU), published as looped RTSP streams |

Dashboard: `http://<HOST_IP>:4173`

---

## 🚀 Running the demo

```bash
./run-demo-captioning.sh
```

The script performs the whole documented application flow:

1. Stops anything left over from a previous session (`stop-all-demos.sh`).
2. Regenerates `../live-video-captioning/.env` with `scripts/setup_env.sh --force`
   so `HOST_IP` always matches the current network.
3. Downloads and converts the VLM for the **GPU** on first run
   (`OpenGVLab/InternVL2-1B`, `int8`) — this takes several minutes once.
4. Starts the stack with `docker compose` using `.env` plus the showroom
   overrides in `captioning-demo.env`.
5. Publishes `videos/*.mp4` as looped RTSP streams and starts the four runs
   from `pipelines.json` (`run-pipelines.sh`).
6. Opens the dashboard in the browser and keeps running.

Press **Ctrl+C** to stop — containers, RTSP streams and the ffmpeg publishers
are all shut down.

### Showroom appliance (Wi-Fi access point + remote start)

For the unattended showroom setup — Ubuntu host with its own `IntelDemoWLAN`
access point, started remotely from a Windows laptop — use:

| File | Purpose |
|------|---------|
| [`setup-showroom-host.sh`](setup-showroom-host.sh) | One-shot preparation of the Ubuntu host (repo at a pinned commit, access point, key-based SSH account, dependencies, one-time model conversion, desktop launcher) |
| [`StartPreview.ps1`](StartPreview.ps1) + [`RunDemo.bat`](RunDemo.bat) | Windows client: connects to the access point, starts the demo over SSH with `HOST_IP=192.168.100.1` and opens the dashboard |
| [`remote-preview-setup.md`](remote-preview-setup.md) | Full setup and troubleshooting guide |
| [`end-user-guide.md`](end-user-guide.md) | Short operating instructions for the person running the demo at the booth |

### Relation to the application quick start

The demo automates the [quick start guide](../live-video-captioning/docs/user-guide/quick-start-guide.md)
with these showroom-specific choices:

| Quick start step | Demo behaviour | Why |
|------------------|----------------|-----|
| `bash scripts/setup_env.sh` | `setup_env.sh --force` | The showroom machine changes networks; `HOST_IP` must be re-detected on every start. |
| `download_models.sh ... --weight-format int8` (CPU default) | same command with `--device GPU`, skipped when `ov_models/gpu/<model>` exists | The demo pins inference to the integrated GPU; the guard keeps it a one-time step. |
| `docker compose up -d` | `--env-file .env --env-file captioning-demo.env` | Keeps showroom settings in version control instead of hand-editing the regenerated `.env`. |
| Configure the run in the dashboard | `run-pipelines.sh` posts the runs to the documented REST API | Four sources have to start unattended before the browser opens. |
| Simulated RTSP stream guide | `scripts/setup_proxy_rtsp.sh` publishes `videos/*.mp4` | Same helper the documentation recommends. |

> Because `.env` is regenerated, put gated-model credentials in the shell, not in
> the file: `export HUGGINGFACEHUB_API_TOKEN=<token>` before starting the demo —
> the launcher re-applies it to `.env` after regeneration.

---

<details>
<summary>🔧 First-time setup</summary>

**1. Install system dependencies** (Docker, ffmpeg, jq, V4L2 utilities):

```bash
./install-dependencies.sh
```

**2. Connect a USB camera** — any UVC webcam that provides MJPG/YUYV output.
Verify it is detected:

```bash
ls /dev/video*          # expect /dev/video0
./list-camera-formats.sh
```

If the device node differs, change `cameraDevice` in `pipelines.json`.

**3. Add three demo videos.** The `videos/` directory is **not** part of the
repository (it is git-ignored). Copy your own clips into it:

```bash
mkdir -p videos
cp /path/to/*.mp4 videos/
```

Files are matched to the `"source": "file"` entries of `pipelines.json` in
alphabetical order. With fewer files, the remaining runs are skipped with a
warning.

</details>

<details>
<summary>⚙️ Configuration</summary>

**`captioning-demo.env`** — overrides applied on top of the application `.env`:

| Variable | Default | Description |
|----------|---------|-------------|
| `REGISTRY` | `intel/` | Docker image registry prefix |
| `TAG` | `latest` | Docker image tag |
| `ALERT_MODE` | `true` | Alert-style highlighting in the dashboard |
| `ENABLE_DETECTION_PIPELINE` | `false` | Object detection stays off in this demo |
| `CAPTION_HISTORY` | `3` | Number of previous captions shown |
| `WEBRTC_BITRATE` | `2048` | WebRTC bitrate in kbps |
| `VLM_CACHE_SIZE` | `4` | KV-cache size per run. Each run loads its own VLM instance — the pipelines do not share the model — so lower it only if the concurrent streams stop fitting into GPU memory. |

**`pipelines.json`** — the four demo runs. Top-level keys apply to all runs:
`vlmDevice` (`gpu`), `pipelineType` (`non-detection`), `cameraDevice`, plus the
shared run defaults `maxNewTokens`, `frameRate` and `chunkSize`. Every run defines
`runName`, `source` (`camera` or `file`) and `prompt`, and may override any default
(including the optional `frameWidth`/`frameHeight`).

> **Latency tuning:** the demo deliberately leaves `frameWidth`/`frameHeight` unset,
> which selects the `*_Default_Resolution` pipelines and keeps the source resolution.
> Measurements on the showroom machine showed this to be *faster* than forcing a
> smaller frame (the extra scaling step costs more than the tokens it saves):
> camera alone ≈1.6 s TTFT / <1 s lag, and with all four runs ≈1.5 s TTFT / ~2 s lag
> for the file streams. `maxNewTokens` remains the most direct lever on caption lag.

**Script overrides** (environment variables):

```bash
VLM_MODEL=OpenGVLab/InternVL2-2B ./run-demo-captioning.sh
./run-pipelines.sh --config my-pipelines.json --videos /data/clips
```

</details>

---

## 🛠️ Troubleshooting

| Symptom | Fix |
|---------|-----|
| `Run ... was not ready in 300s` for the file runs | The pipeline server cannot pull `rtsp://<HOST_IP>:8554/streamN`. Add the host IP (and your local ranges) to `no_proxy` in `/etc/environment`, then `source /etc/environment` and restart the demo. See [known issues](../live-video-captioning/docs/user-guide/known-issues.md#rtsp-stream-not-reachable-from-live-video-captioning-application). |
| `Pipeline server unreachable ... Temporary failure in name resolution` | `dlstreamer-pipeline-server` exited, so Docker DNS cannot resolve it. Inspect `docker logs dlstreamer-pipeline-server` — usually resource pressure from too many concurrent GPU streams or a proxy-related segfault. Reduce the number of runs in `pipelines.json` or lower `frameWidth`/`frameHeight`. |
| Only some runs start | Concurrent GPU capacity is limited; scale gradually (start with camera + 1 file run) and check `docker stats` / the dashboard metrics. |
| One run has much higher TTFT/lag than the others | Compare `maxNewTokens` and the frame resolution in `pipelines.json`. Forcing `frameWidth`/`frameHeight` adds a scaling step that on this hardware costs more than it saves — leaving them unset (Default resolution) measured fastest. |
| The USB camera lags more than the file streams under load | Expected with four concurrent GPU pipelines: the live capture keeps the GPU busy alongside inference. Run fewer streams if the camera lag matters most. |
| `No VLM model available for device 'gpu'` | Rerun the demo; it converts the model, or run `../live-video-captioning/model_download_scripts/download_models.sh --model OpenGVLab/InternVL2-1B --type vlm --weight-format int8 --device GPU` |
| Camera run is skipped | `/dev/video0` missing — check `ls /dev/video*` and `cameraDevice` in `pipelines.json` |
| File runs are skipped | No `*.mp4` files in `videos/` |
| RTSP streams do not start | Inspect `.rtsp-publisher.log` and `docker logs mediamtx-server` |
| Service never becomes healthy | `docker logs video-caption-service` |
| Pipeline goes to error state | `docker logs dlstreamer-pipeline-server` |
| Video panel shows nothing in Firefox | H.264 missing — see **Firefox H.264 fix** below |
| Stream behind a corporate proxy | Add `HOST_IP` to `no_proxy` before starting the demo |

**Firefox H.264 fix** — Firefox on Ubuntu (especially Snap) may lack H.264 support:

1. Run `./install-dependencies.sh`.
2. In `about:config` verify `media.gmp-gmpopenh264.enabled` and
   `media.peerconnection.video.h264_enabled` are `true`.
3. Restart Firefox.

---

## 📚 Reference

- 📄 [live-video-captioning — Quick Start](../live-video-captioning/docs/user-guide/quick-start-guide.md)
- 📄 [live-video-captioning — Get Started](../live-video-captioning/docs/user-guide/get-started.md)
- 📄 [Simulated RTSP streams](../live-video-captioning/docs/user-guide/get-started/simulated-rtsp-stream-guide.md)
- 📄 [Remote preview setup](remote-preview-setup.md) — showroom host + Windows client
- 📄 [End-user guide](end-user-guide.md) — booth operating instructions
- 📁 [`deprecated/`](./deprecated/README.md) — scripts from the previous showroom flow

