# Live Video Captioning Demo — End-User Guide

This demo runs on the NUC device and is previewed from a laptop.

## Overview

- The **NUC** runs the captioning application and creates the `IntelDemoWLAN` Wi-Fi network.
- The **laptop** connects to that network, starts the demo and shows the dashboard.

## A. Starting the demo from the laptop

1. Connect the NUC device to a power outlet.
2. Plug the USB camera into one of the NUC device's USB ports.
3. Turn on the NUC device using the power button on the front panel.
4. Turn on your laptop.
5. Make sure the laptop has both required files in the same folder:
   - `StartPreview.ps1`
   - `RunDemo.bat`

   On the first run they are copied to the laptop automatically and an **Intel Showroom Demo**
   shortcut appears on the desktop — from then on you can start the demo from that shortcut.
6. Double-click **RunDemo** to start the demo.
7. The first time you run the demo you may be asked for:
   - an SSH key passphrase — press **Enter** to skip it (and **Enter** again to confirm),
   - the Wi-Fi password for `IntelDemoWLAN` — ask the demo owner for it,
   - an SSH password — only if the laptop key has not been installed on the NUC yet.
8. Wait until the script reports **Demo ready**. The first start can take several minutes because
   the application prepares the AI model.
9. A browser window opens automatically with the captioning dashboard.

If this does not work, use Option B below.

### Closing the demo safely (Option A)

1. Close the browser window first.
2. Click the terminal window that opened when you started **RunDemo**.
3. Press **Enter** to stop the demo safely.
4. To turn off the NUC device, follow [Turning off the NUC device safely](#turning-off-the-nuc-device-safely).

## B. Starting the demo on the device directly (fallback)

Use this option only if Option A fails.

Requirements: keyboard, mouse, monitor.

1. Connect the NUC device to a power outlet.
2. Plug the USB camera into one of the NUC device's USB ports.
3. Plug the keyboard and mouse into the NUC device's ports.
4. Turn on the NUC device using the power button on the front panel.
5. At the login screen sign in as **sshuser** using the provided credentials.
6. Find **RunDemo** on the desktop and double-click it to start the demo.
7. The browser opens automatically once the demo is ready.

### Closing the demo safely (Option B)

1. Close the browser window first.
2. Click the terminal window that opened when you started **RunDemo**.
3. Press **Ctrl + C** to stop the demo safely.

## What you see in the dashboard

The demo starts its captioning runs automatically — nothing has to be typed in the user interface:

- one run for the **USB camera**,
- one run for each demo video preinstalled on the NUC.

Every run shows the live video together with the natural-language captions generated for it.

## Changing the demo videos

The demo videos are preinstalled on the NUC. To use different clips, copy `*.mp4` files into the
`videos` folder of the demo, which is also reachable as:

```text
/home/sshuser/showroom-demo/videos
```

Restart the demo afterwards — each file becomes one captioning run.

## Turning off the NUC device safely

1. Locate the power button on the NUC device's front panel.
2. Press and hold the power button until the light turns off.
3. You can now safely unplug the NUC device from the power outlet.

## If something stops working

1. **The script cannot connect and a globe icon appears in the bottom-left corner of the screen**
   — restart your laptop.
2. **The script shows yellow text or `RETRYABLE_SSH_FAILURE`** — the laptop dropped off the
   `IntelDemoWLAN` network. Reconnect to it manually and let the script retry.
3. **The video stops or the metrics do not update** — refresh the dashboard page in the browser.
4. **The dashboard opens but no video appears** — stop the demo (see above) and start it again;
   if it persists, hand the device over to the demo owner and see
   [remote-preview-setup.md](remote-preview-setup.md).

