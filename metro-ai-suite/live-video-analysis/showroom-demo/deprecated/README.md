# Deprecated showroom scripts

These scripts belong to the previous showroom flow and are kept only for
reference. They are **not** used by `run-demo-captioning.sh` anymore.

| File | Why it was retired |
|------|--------------------|
| `camera-rtsp.py` | The captioning application consumes USB cameras directly (`/dev/videoX`), and video files are published by the application's own `scripts/setup_proxy_rtsp.sh`. |
| `run-demo-alert.sh` | The alert-agent demo is not part of the current showroom setup. |
| `run-pipelines1.sh`, `run-pipelines2.sh` | Replaced by `run-pipelines.sh` + `pipelines.json`. They still send the removed `pipelineName` field, which the current API rejects. |
| `fix-keyframes.sh` | Only needed by the old `camera-rtsp.py` file-looping approach. |
| `stop-containers.sh` | Removed every container on the host; `stop-all-demos.sh` stops only the demo stack. |

