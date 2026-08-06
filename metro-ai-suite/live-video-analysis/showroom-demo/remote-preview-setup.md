# Live Video Captioning — Remote Preview Setup

This guide explains how to run the [live-video-captioning](../live-video-captioning) showroom demo
on an Ubuntu host and preview it remotely from a Windows laptop.

> **Shortcut:** instead of following the Ubuntu steps manually you can run
> [`setup-showroom-host.sh`](setup-showroom-host.sh), which performs all of them and prints a
> summary of what succeeded.

## Table of contents

1. [Overview](#overview)
2. [Architecture](#architecture)
3. [Prerequisites](#prerequisites)
4. [Ubuntu host setup](#ubuntu-host-setup)
    - 4.1 [Automated setup](#automated-setup)
    - 4.2 [Install dependencies](#install-dependencies)
    - 4.3 [Get the demo](#get-the-demo)
    - 4.4 [Configure the access point](#configure-the-access-point)
    - 4.5 [Configure the SSH server](#configure-the-ssh-server)
    - 4.6 [Install the demo dependencies](#install-the-demo-dependencies)
    - 4.7 [Add demo videos](#add-demo-videos)
    - 4.8 [Convert the model once](#convert-the-model-once)
    - 4.9 [Create the fallback launcher](#create-the-fallback-launcher)
5. [Windows client setup](#windows-client-setup)
6. [Verification steps](#verification-steps)
7. [Troubleshooting](#troubleshooting)
8. [Security notes](#security-notes)
9. [Known issues](#known-issues)

## Overview

The Ubuntu machine:

- hosts the demo (`run-demo-captioning.sh`)
- creates a Wi-Fi access point (`IntelDemoWLAN`, `192.168.100.1/24`)
- serves the captioning dashboard on port `4173`

The Windows machine:

- connects to the Ubuntu access point
- starts the demo remotely over SSH
- opens the dashboard in a browser

## Architecture

```text
USB camera + videos/*.mp4 -> live-video-captioning (GPU) -> dashboard + WebRTC -> Windows client
```

Communication between Ubuntu and Windows uses SSH for the remote start/stop and HTTP/WebRTC for
the dashboard and video preview.

`HOST_IP` decides which address the application publishes for WebRTC and the simulated RTSP
streams. The Windows client always starts the demo with `HOST_IP=192.168.100.1` (the access point
address), because the host's default route may point at a different interface.

## Prerequisites

- Ubuntu 24.04 with an Intel GPU (`/dev/dri`)
- Windows 11 with OpenSSH client (built in)
- USB camera (UVC, MJPG/YUYV)
- Internet connection for the first setup (images and model download)

## Ubuntu host setup

### Automated setup

Clone the repository wherever the demo should live — the setup script works **in place**, on the
checkout it is part of, so nothing is downloaded behind your back and the running revision is
exactly the one you checked out.

Pick a location every account can reach (a private home directory is not traversable for
`sshuser`), for example:

```bash
sudo install -d -o "$USER" /opt/showroom
git clone https://github.com/open-edge-platform/edge-ai-suites-prv.git /opt/showroom/edge-ai-suites
cd /opt/showroom/edge-ai-suites
git checkout <commit-to-pin>          # optional: pin a validated revision
cd metro-ai-suite/live-video-analysis/showroom-demo
AP_PASSWORD='<wifi-password>' SSH_PUBKEY=~/laptop-key.pub ./setup-showroom-host.sh
```

The script reports the installed revision (`git rev-parse --short HEAD`, remote URL, local
modifications) and, at the end, the `$demoDir` value to use on the Windows laptop.

| Variable | Default | Meaning |
|----------|---------|---------|
| `AP_SSID` / `AP_IP` | `IntelDemoWLAN` / `192.168.100.1` | Access point |
| `AP_PASSWORD` | *(prompt)* | WPA2 passphrase — never stored in the repository |
| `SSHUSER` | `sshuser` | Unprivileged account used for the remote start |
| `SSH_PUBKEY` | *(empty)* | Public key of the laptop; when set, password login is disabled |
| `VLM_MODEL` / `WEIGHT_FORMAT` | `OpenGVLab/InternVL2-1B` / `int8` | Model converted for the GPU |

The remaining sections describe the same steps performed manually.

### Install dependencies

```bash
sudo apt update
sudo apt install -y git tmux curl openssh-server network-manager
```

### Get the demo

```bash
sudo install -d -o "$USER" /opt/showroom
git clone https://github.com/open-edge-platform/edge-ai-suites-prv.git /opt/showroom/edge-ai-suites
cd /opt/showroom/edge-ai-suites
git checkout <commit-to-pin>
```

The repository is public, so the clone needs no credentials. Checking out a specific commit pins
both `live-video-captioning` and `showroom-demo` to a validated combination.

Share the checkout with the demo account (group access, not `chmod 777`, and the owner stays
unchanged):

```bash
cd metro-ai-suite/live-video-analysis
sudo chgrp -R sshuser showroom-demo live-video-captioning
sudo chmod -R g+rwX showroom-demo live-video-captioning
sudo find showroom-demo live-video-captioning -type d -exec chmod g+s {} +
```

### Configure the access point

> NOTE: replace `wlan0` with your actual wireless interface (`nmcli device`).

```bash
nmcli connection add \
    type wifi \
    ifname wlan0 \
    con-name IntelDemoWLAN \
    autoconnect yes \
    ssid IntelDemoWLAN

nmcli connection modify IntelDemoWLAN \
    802-11-wireless.band a \
    802-11-wireless.mode ap \
    802-11-wireless-security.key-mgmt wpa-psk \
    802-11-wireless-security.psk "<wifi-password>" \
    802-11-wireless-security.pmf disable \
    ipv4.method shared \
    ipv4.addresses 192.168.100.1/24

nmcli connection up IntelDemoWLAN
```

Verify that the `IntelDemoWLAN` network appears and that the host owns `192.168.100.1`.

### Configure the SSH server

```bash
sudo systemctl enable --now ssh.service

sudo useradd -m -s /bin/bash sshuser
sudo usermod -aG video,render,docker sshuser   # camera, GPU and Docker access
```

Install the laptop's public key and switch the account to key-only login:

```bash
sudo install -d -m 0700 -o sshuser -g sshuser /home/sshuser/.ssh
sudo tee -a /home/sshuser/.ssh/authorized_keys < laptop-key.pub
sudo chmod 600 /home/sshuser/.ssh/authorized_keys
sudo chown sshuser:sshuser /home/sshuser/.ssh/authorized_keys

sudo tee /etc/ssh/sshd_config.d/60-showroom-demo.conf <<'EOF'
Match User sshuser
    PasswordAuthentication no
    KbdInteractiveAuthentication no
    X11Forwarding no
    AllowTcpForwarding no
EOF
sudo systemctl restart ssh.service
```

`StartPreview.ps1` generates `~/.ssh/id_ed25519_LiveDemoKey` on the laptop — use
`id_ed25519_LiveDemoKey.pub` as `laptop-key.pub`. If the key is not installed up front, leave
password authentication enabled for the first run and disable it afterwards.

### Install the demo dependencies

```bash
cd /opt/showroom/edge-ai-suites/metro-ai-suite/live-video-analysis/showroom-demo
chmod +x install-dependencies.sh run-demo-captioning.sh run-pipelines.sh stop-all-demos.sh
./install-dependencies.sh
```

Behind a corporate proxy the pipeline server must bypass it for the host address, otherwise the
RTSP streams stall:

```bash
echo 'no_proxy="localhost,127.0.0.1,192.168.100.1,host.docker.internal"' | sudo tee -a /etc/environment
echo 'NO_PROXY="localhost,127.0.0.1,192.168.100.1,host.docker.internal"' | sudo tee -a /etc/environment
```

### Add demo videos

The `videos/` directory is git-ignored; copy the clips used at the show into it:

```bash
mkdir -p videos
cp /path/to/*.mp4 videos/
```

Each `*.mp4` is published as a looped RTSP stream and matched to a `"source": "file"` entry of
`pipelines.json` in alphabetical order.

### Convert the model once

```bash
../live-video-captioning/model_download_scripts/download_models.sh \
  --model OpenGVLab/InternVL2-1B --type vlm --weight-format int8 --device GPU
```

`run-demo-captioning.sh` performs this automatically on the first run, but doing it during setup
keeps the show-time start short.

### Create the fallback launcher

Create `/home/sshuser/Desktop/RunDemo.desktop` (adjust the path to your checkout):

```ini
[Desktop Entry]
Type=Application
Name=RunDemo
Exec=gnome-terminal -- bash -c "HOST_IP=192.168.100.1 '/opt/showroom/edge-ai-suites/metro-ai-suite/live-video-analysis/showroom-demo/run-demo-captioning.sh'"
Icon=utilities-terminal
Terminal=false
```

```bash
chmod +x /home/sshuser/Desktop/RunDemo.desktop
```

In the file manager right-click the file and choose **Allow launching**. Double-clicking it then
starts the demo and opens the dashboard on the host itself.

## Windows client setup

Copy [`RunDemo.bat`](RunDemo.bat) and [`StartPreview.ps1`](StartPreview.ps1) onto the laptop (any
folder, USB stick included) and double-click `RunDemo.bat`. **No paths have to be configured:**

- on the first run the client copies itself into `%LOCALAPPDATA%\IntelShowroomDemo` and creates an
  *Intel Showroom Demo* shortcut on the desktop, so later starts need neither the repository nor
  the USB stick;
- the demo location on the host is discovered over SSH from `~sshuser/.showroom-demo`, which
  `setup-showroom-host.sh` writes (with a `~sshuser/showroom-demo` symlink as a second source).

Override the defaults only if you changed them on the host:

| Variable | Default | Meaning |
|----------|---------|---------|
| `$SSID` | `IntelDemoWLAN` | Access point name |
| `$remoteHostAddress` / `$hostIp` | `192.168.100.1` | Host address, also passed as `HOST_IP` |
| `$port` | `4173` | Dashboard port (`DASHBOARD_PORT`) |
| `$remoteUser` | `sshuser` | SSH account |
| `$demoDir` | *(discovered)* | Fallback only; force it with `$env:SHOWROOM_DEMO_DIR` |
| `$readyTimeoutSeconds` | `1800` | How long to wait for `/api/health` |

The Wi-Fi password is **not** stored in the script. Either export it before starting:

```powershell
$env:INTEL_DEMO_WLAN_PASSWORD = '<wifi-password>'
```

or type it when the script prompts for it.

The script connects to the access point, installs its SSH key if needed, resolves the demo
location, starts the demo in a `tmux` session, waits for
`http://192.168.100.1:4173/api/health` and opens the dashboard. Press **Enter** in the terminal
window to stop the demo — it runs `stop-all-demos.sh` on the host and restores the previous
Wi-Fi network.

## Verification steps

1. The `IntelDemoWLAN` network is visible from the laptop.
2. SSH works: `ssh -i ~/.ssh/id_ed25519_LiveDemoKey sshuser@192.168.100.1`
3. Containers are running: `docker ps` (expect `video-caption-service`, `dlstreamer-pipeline-server`, `mediamtx`)
4. The dashboard answers: `curl http://192.168.100.1:4173/api/health`

## Troubleshooting

Demo-level problems (pipelines, GPU capacity, RTSP, Firefox H.264) are covered in the
[README](README.md#-troubleshooting). This section covers the remote-preview setup only.

### Access point does not appear

```bash
iw list | grep AP          # the adapter must support AP mode
```

### Permission denied when accessing the camera or GPU

```bash
groups sshuser             # expect video, render and docker
```

### Windows cannot connect over SSH

```bash
ip addr                    # confirm 192.168.100.1 is assigned
sudo systemctl status ssh.service
```

### The dashboard opens but no video is shown

`HOST_IP` does not match the access point address — WebRTC then advertises an unreachable host.
Start the demo with `HOST_IP=192.168.100.1` (the client script and the desktop launcher do this).

## Security notes

- `sshuser` has **no sudo privileges**, but it is a member of the `docker` group so that the demo
  can be started without `sudo`. Docker group membership is **root-equivalent** on the host —
  keep the account for the demo only, and treat the access point as a closed, trusted network.
- Prefer key-based SSH login (`SSH_PUBKEY`); the script then disables password and
  keyboard-interactive authentication for `sshuser` and validates the sshd config with `sshd -t`
  before restarting the service.
- The Windows client verifies the host key trust-on-first-use: it is stored in
  `~/.ssh/known_hosts_livedemo` and checked on every later connection
  (`StrictHostKeyChecking=accept-new`).
- No passwords are stored in the repository: the Wi-Fi passphrase comes from `AP_PASSWORD` /
  `INTEL_DEMO_WLAN_PASSWORD` or an interactive prompt. The Windows WLAN profile that carries the
  passphrase is deleted from `%TEMP%` right after it is imported.
- Known limitation: `nmcli` receives the WPA2 passphrase as a command-line argument, so it is
  briefly visible in the host's process list while the access point is being configured.
- The one-time model conversion uses the application's `download_models.sh`, which fetches and
  runs a helper script from `raw.githubusercontent.com/open-edge-platform/edge-ai-libraries`.
  Run the setup only on a network where that source is trusted.
- Ports `4173` (dashboard), `8554`/`8556` (RTSP), `8889`/`8189` (WebRTC) and `3478` (TURN) are
  exposed on the demo network without authentication — this is the application's design and is a
  deployment-time consideration, so keep the access point isolated from production networks.

## Known issues

### Windows 11 cannot connect to the remote preview

- **Symptoms:** the browser never opens; SSH fails with `port 22 unreachable`.
- **Cause:** Wi-Fi AP-mode compatibility issues on some adapters.
- **Workaround:** keep `802-11-wireless-security.pmf disable`, reconnect the client, and if needed
  `sudo systemctl restart NetworkManager`.

### Windows 11 suddenly switches to another network

- **Symptoms:** sudden network errors during the script run; the preview freezes.
- **Workaround:** keep the AP on the 5 GHz band
  (`nmcli connection modify IntelDemoWLAN 802-11-wireless.band a`).

### No video when starting the preview remotely

- **Symptoms:** the dashboard opens, but the camera run is missing.
- **Cause:** the remote user is not in the `video` (camera) or `render` (GPU) group.
- **Workaround:** `sudo usermod -aG video,render sshuser` and reconnect.

