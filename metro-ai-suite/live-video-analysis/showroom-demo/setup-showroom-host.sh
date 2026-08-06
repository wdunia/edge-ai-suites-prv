#!/usr/bin/env bash
# Prepares an Ubuntu showroom host for the live-video-captioning demo:
#   1. installs the base tooling
#   2. creates the unprivileged demo account used for remote start (sshuser)
#   3. grants that account access to this checkout
#   4. brings up the IntelDemoWLAN access point (192.168.100.1/24)
#   5. configures the SSH server for key-based login
#   6. installs the demo dependencies (Docker, ffmpeg, jq, GStreamer, ...)
#   7. downloads and converts the VLM once, for the GPU
#   8. creates a desktop launcher as a fallback when the laptop cannot connect
#
# The demo is installed in place: everything operates on the repository checkout
# this script was cloned into, so the running revision is whatever you checked
# out (pin it with 'git checkout <commit>' before running the setup).
#
# The remote client counterpart is StartPreview.ps1 / RunDemo.bat.
#
# 'set -e' is intentionally omitted: every step reports its own status in the
# summary printed at the end, so a single failing step must not abort the run.
set -uo pipefail

# --------------------------------------------------------------- configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEMO_DIR="${SCRIPT_DIR}"
APP_DIR="$(cd "${SCRIPT_DIR}/../live-video-captioning" 2>/dev/null && pwd || echo "")"

# Access point. The password is never stored in the repository: provide it in
# AP_PASSWORD or type it when prompted.
AP_CON_NAME="${AP_CON_NAME:-IntelDemoWLAN}"
AP_SSID="${AP_SSID:-IntelDemoWLAN}"
AP_IP="${AP_IP:-192.168.100.1}"
AP_PREFIX="${AP_PREFIX:-24}"
AP_PASSWORD="${AP_PASSWORD:-}"

# Unprivileged account used by StartPreview.ps1. SSH_PUBKEY may be a path to a
# public key file or the key itself; when set, password login is disabled.
SSHUSER="${SSHUSER:-sshuser}"
SSH_PUBKEY="${SSH_PUBKEY:-}"

# VLM converted once during setup so the first demo run is fast.
VLM_MODEL="${VLM_MODEL:-OpenGVLab/InternVL2-1B}"
WEIGHT_FORMAT="${WEIGHT_FORMAT:-int8}"
VLM_DEVICE="GPU"

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
NO_COLOR='\033[0m'

STEPS=(
	"Install base dependencies"
	"Create demo user: ${SSHUSER}"
	"Grant ${SSHUSER} access to the checkout"
	"Create Wi-Fi access point"
	"Configure SSH server"
	"Install demo dependencies"
	"Download and convert the VLM (GPU)"
	"Create desktop fallback launcher"
)
statuses=()
for _ in "${STEPS[@]}"; do
	statuses+=("PENDING")
done

mark() { statuses[$1]="$2"; }
info() { echo -e "${GREEN}$*${NO_COLOR}"; }
warn() { echo -e "${YELLOW}$*${NO_COLOR}" >&2; }
fail() { echo -e "${RED}$*${NO_COLOR}" >&2; }

if [[ "$(id -u)" -eq 0 ]]; then
	fail "Run this script as a regular user with sudo rights, not as root."
	exit 1
fi

# ------------------------------------------------- 1. install base dependencies
sudo apt update
if sudo apt install -y git tmux curl openssh-server network-manager; then
	mark 0 DONE
	info "Installed base dependencies: git, tmux, curl, openssh-server, network-manager"
else
	mark 0 FAILED
	fail "Failed to install the base dependencies"
fi

# ----------------------------------------------------------- 2. create the user
if id "${SSHUSER}" &>/dev/null; then
	mark 1 EXISTED_BEFORE
	info "User ${SSHUSER} already exists"
elif sudo useradd -m -s /bin/bash "${SSHUSER}"; then
	mark 1 DONE
	info "Created user ${SSHUSER}"
else
	mark 1 FAILED
	fail "Failed to create user ${SSHUSER}"
fi

SSHUSER_HOME="$(getent passwd "${SSHUSER}" | cut -d: -f6)"

# --------------------------------------------- 3. share the checkout with the user
if [[ -z "${APP_DIR}" ]]; then
	mark 2 FAILED
	fail "live-video-captioning not found next to ${DEMO_DIR} - run this script from a full checkout"
else
	# The demo runs as ${SSHUSER} and writes .env, ov_models and videos, so the
	# checkout is shared through the group instead of world-writable permissions
	# (no chmod 777) and without taking it away from the installing user.
	if sudo chgrp -R "${SSHUSER}" "${DEMO_DIR}" "${APP_DIR}" &&
		sudo chmod -R g+rwX "${DEMO_DIR}" "${APP_DIR}" &&
		sudo find "${DEMO_DIR}" "${APP_DIR}" -type d -exec chmod g+s {} +; then
		mark 2 DONE
		info "Shared ${DEMO_DIR} and ${APP_DIR} with the ${SSHUSER} group"
	else
		mark 2 FAILED
		fail "Failed to grant ${SSHUSER} access to the checkout"
	fi

	install -d -m 0775 "${DEMO_DIR}/videos" 2>/dev/null ||
		sudo install -d -m 0775 -g "${SSHUSER}" "${DEMO_DIR}/videos"

	for demo_script in install-dependencies.sh run-demo-captioning.sh run-pipelines.sh \
		stop-all-demos.sh list-camera-formats.sh; do
		if [[ -f "${DEMO_DIR}/${demo_script}" ]]; then
			sudo chmod 775 "${DEMO_DIR}/${demo_script}"
		else
			warn "Expected demo script is missing: ${DEMO_DIR}/${demo_script}"
		fi
	done

	# ${SSHUSER} must be able to traverse every parent directory of the checkout.
	# A checkout under a private home directory (0750) is not reachable for it.
	if ! sudo -u "${SSHUSER}" test -x "${DEMO_DIR}"; then
		warn "${SSHUSER} cannot reach ${DEMO_DIR} (a parent directory is not traversable)."
		warn "Move the checkout to a shared location, for example /opt or /IntelOpenEdge, and rerun this script."
	fi

	# Record which revision is installed - useful when debugging a showroom unit.
	if git -C "${DEMO_DIR}" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
		info "Installed revision: $(git -C "${DEMO_DIR}" rev-parse --short HEAD) from $(git -C "${DEMO_DIR}" remote get-url origin 2>/dev/null || echo 'unknown remote')"
		if [[ -n "$(git -C "${DEMO_DIR}" status --porcelain 2>/dev/null)" ]]; then
			warn "The checkout has local modifications - the demo runs exactly what is on disk."
		fi
	else
		warn "${DEMO_DIR} is not a git checkout; the running revision cannot be reported."
	fi

	# Publish the location so the Windows client discovers it over SSH and needs
	# no manual path configuration at all.
	if [[ -n "${SSHUSER_HOME}" ]]; then
		printf '%s\n' "${DEMO_DIR}" | sudo tee "${SSHUSER_HOME}/.showroom-demo" >/dev/null
		sudo chmod 644 "${SSHUSER_HOME}/.showroom-demo"
		sudo chown "${SSHUSER}:${SSHUSER}" "${SSHUSER_HOME}/.showroom-demo"
		sudo ln -sfn "${DEMO_DIR}" "${SSHUSER_HOME}/showroom-demo"
		sudo chown -h "${SSHUSER}:${SSHUSER}" "${SSHUSER_HOME}/showroom-demo"
	fi
fi

# ------------------------------------------------------- 4. Wi-Fi access point
WIFI_INTERFACE="$(nmcli -t -f DEVICE,TYPE device | awk -F: '$2=="wifi"{print $1; exit}')"
if [[ -z "${WIFI_INTERFACE}" ]]; then
	mark 3 FAILED
	fail "No Wi-Fi interface found, skipping the access point configuration"
else
	if [[ -z "${AP_PASSWORD}" ]]; then
		read -rsp "Wi-Fi password for ${AP_SSID} (min. 8 characters, not stored in the repo): " AP_PASSWORD
		echo
	fi

	if [[ "${#AP_PASSWORD}" -lt 8 ]]; then
		mark 3 FAILED
		fail "The WPA2 password must be at least 8 characters long"
	else
		nmcli connection delete "${AP_CON_NAME}" >/dev/null 2>&1 || true
		# The PSK is taken from the environment/prompt and lands only in the
		# NetworkManager keystore (/etc/NetworkManager/system-connections, 0600).
		# Limitation: nmcli takes the PSK as an argument, so it is briefly
		# visible in the process list of this host while the command runs.
		if nmcli connection add \
			type wifi \
			ifname "${WIFI_INTERFACE}" \
			con-name "${AP_CON_NAME}" \
			autoconnect yes \
			ssid "${AP_SSID}" >/dev/null &&
			nmcli connection modify "${AP_CON_NAME}" \
				802-11-wireless.band a \
				802-11-wireless.mode ap \
				802-11-wireless-security.key-mgmt wpa-psk \
				802-11-wireless-security.psk "${AP_PASSWORD}" \
				802-11-wireless-security.pmf disable \
				ipv4.method shared \
				ipv4.addresses "${AP_IP}/${AP_PREFIX}"; then
			mark 3 DONE
			info "Added network ${AP_SSID} on interface '${WIFI_INTERFACE}' (${AP_IP})"
		else
			mark 3 FAILED
			fail "Failed to configure the access point"
		fi
	fi
	unset AP_PASSWORD
fi

# ---------------------------------------------------------- 5. SSH server setup
sudo systemctl enable --now ssh.service >/dev/null 2>&1
sudo systemctl restart ssh.service

if [[ -n "${SSH_PUBKEY}" && -n "${SSHUSER_HOME}" ]]; then
	if [[ -f "${SSH_PUBKEY}" ]]; then
		PUBKEY_DATA="$(cat "${SSH_PUBKEY}")"
	else
		PUBKEY_DATA="${SSH_PUBKEY}"
	fi

	# Validate before trusting it: only a well-formed public key may end up in
	# authorized_keys, and never a private key pasted by mistake.
	PUBKEY_TMP="$(mktemp)"
	printf '%s\n' "${PUBKEY_DATA}" > "${PUBKEY_TMP}"
	if ! ssh-keygen -l -f "${PUBKEY_TMP}" >/dev/null 2>&1; then
		rm -f "${PUBKEY_TMP}"
		mark 4 FAILED
		fail "SSH_PUBKEY is not a valid OpenSSH public key"
	elif grep -qi "PRIVATE KEY" "${PUBKEY_TMP}"; then
		rm -f "${PUBKEY_TMP}"
		mark 4 FAILED
		fail "SSH_PUBKEY looks like a PRIVATE key - refusing to install it"
	else
		sudo install -d -m 0700 -o "${SSHUSER}" -g "${SSHUSER}" "${SSHUSER_HOME}/.ssh"
		sudo touch "${SSHUSER_HOME}/.ssh/authorized_keys"
		# Idempotent: do not append the same key twice on repeated runs.
		if ! sudo grep -qxF "$(cat "${PUBKEY_TMP}")" "${SSHUSER_HOME}/.ssh/authorized_keys"; then
			sudo tee -a "${SSHUSER_HOME}/.ssh/authorized_keys" < "${PUBKEY_TMP}" >/dev/null
		fi
		rm -f "${PUBKEY_TMP}"
		sudo chmod 600 "${SSHUSER_HOME}/.ssh/authorized_keys"
		sudo chown "${SSHUSER}:${SSHUSER}" "${SSHUSER_HOME}/.ssh/authorized_keys"

		# Key-only login for the demo account; the rest of the host is untouched.
		sudo tee /etc/ssh/sshd_config.d/60-showroom-demo.conf >/dev/null <<EOF
Match User ${SSHUSER}
    PasswordAuthentication no
    KbdInteractiveAuthentication no
    X11Forwarding no
    AllowTcpForwarding no
EOF
		sudo chmod 644 /etc/ssh/sshd_config.d/60-showroom-demo.conf
		if sudo sshd -t; then
			sudo systemctl restart ssh.service
			mark 4 DONE
			info "SSH configured for key-based login of ${SSHUSER}"
		else
			sudo rm -f /etc/ssh/sshd_config.d/60-showroom-demo.conf
			mark 4 FAILED
			fail "Rejected sshd configuration (sshd -t failed); the previous configuration is kept"
		fi
	fi
else
	mark 4 SKIPPED
	warn "No SSH_PUBKEY provided - password login stays enabled for ${SSHUSER}."
	warn "Set a password now with: sudo passwd ${SSHUSER}"
	warn "After the laptop has installed its key, rerun this script with SSH_PUBKEY=<path> to enforce key-only login."
fi

# ------------------------------------------------------- 6. demo dependencies
if [[ -x "${DEMO_DIR}/install-dependencies.sh" ]] && bash "${DEMO_DIR}/install-dependencies.sh"; then
	mark 5 DONE
else
	mark 5 FAILED
	fail "Failed to install the demo dependencies"
fi

# Camera, GPU and Docker access for the demo account (groups exist only after
# install-dependencies.sh has installed Docker).
# NOTE: membership in 'docker' is equivalent to root on this host - it is what
# lets the demo be started without sudo. Keep the account for the demo only and
# keep the access point closed to trusted devices.
for grp in video render docker; do
	if getent group "${grp}" >/dev/null; then
		sudo usermod -aG "${grp}" "${SSHUSER}"
	fi
done
warn "${SSHUSER} is now in the 'docker' group, which grants root-equivalent access to this host."

# The pipeline server pulls the RTSP streams from the host IP; behind a proxy
# that must bypass the proxy or the streams stall.
NO_PROXY_ENTRIES="localhost,127.0.0.1,${AP_IP},host.docker.internal"
if ! grep -q "^no_proxy=" /etc/environment 2>/dev/null; then
	printf 'no_proxy="%s"\nNO_PROXY="%s"\n' "${NO_PROXY_ENTRIES}" "${NO_PROXY_ENTRIES}" |
		sudo tee -a /etc/environment >/dev/null
	info "Added no_proxy entries (${NO_PROXY_ENTRIES}) to /etc/environment"
elif ! grep -q "^no_proxy=.*${AP_IP}" /etc/environment; then
	warn "no_proxy is already defined in /etc/environment - add ${AP_IP} to it manually"
fi

# --------------------------------------------------- 7. one-time model download
MODEL_DIR="${APP_DIR}/ov_models/gpu/${VLM_MODEL##*/}"
if [[ -z "${APP_DIR}" ]]; then
	mark 6 FAILED
	fail "live-video-captioning directory not found - skipping the model download"
elif [[ -d "${MODEL_DIR}" ]]; then
	mark 6 EXISTED_BEFORE
	info "VLM already converted: ${MODEL_DIR}"
elif sudo -u "${SSHUSER}" -H bash "${APP_DIR}/model_download_scripts/download_models.sh" \
	--model "${VLM_MODEL}" \
	--type vlm \
	--weight-format "${WEIGHT_FORMAT}" \
	--device "${VLM_DEVICE}"; then
	mark 6 DONE
	info "Converted ${VLM_MODEL} (${WEIGHT_FORMAT}) for the GPU"
else
	mark 6 FAILED
	fail "Model download failed - rerun it later, the demo also converts the model on first start"
fi

# -------------------------------------------------- 8. desktop fallback launcher
DEMO_SCRIPT="${DEMO_DIR}/run-demo-captioning.sh"
if [[ -z "${SSHUSER_HOME}" || ! -d "${SSHUSER_HOME}" ]]; then
	mark 7 FAILED
	fail "Home directory for ${SSHUSER} does not exist!"
elif [[ ! -f "${DEMO_SCRIPT}" ]]; then
	mark 7 FAILED
	fail "Demo script not found at ${DEMO_SCRIPT}"
else
	sudo install -d -m 0755 -o "${SSHUSER}" -g "${SSHUSER}" "${SSHUSER_HOME}/Desktop"
	sudo tee "${SSHUSER_HOME}/Desktop/RunDemo.desktop" >/dev/null <<EOF
[Desktop Entry]
Type=Application
Name=RunDemo
Exec=gnome-terminal -- bash -c "HOST_IP=${AP_IP} '${DEMO_SCRIPT}'"
Icon=utilities-terminal
Terminal=false
EOF
	sudo chmod 755 "${SSHUSER_HOME}/Desktop/RunDemo.desktop"
	sudo chown "${SSHUSER}:${SSHUSER}" "${SSHUSER_HOME}/Desktop/RunDemo.desktop"
	sudo -u "${SSHUSER}" gio set "${SSHUSER_HOME}/Desktop/RunDemo.desktop" metadata::trusted yes 2>/dev/null || true
	mark 7 DONE
fi

# ------------------------------------------------------------------- summary
echo "================================================"
echo "Summary:"
for i in "${!STEPS[@]}"; do
	case "${statuses[$i]}" in
		DONE | EXISTED_BEFORE) COLOR="${GREEN}" ;;
		SKIPPED) COLOR="${YELLOW}" ;;
		*) COLOR="${RED}" ;;
	esac
	echo -e "${COLOR}${statuses[$i]}${NO_COLOR} - ${STEPS[$i]}"
done

echo
echo -e "${CYAN}Demo launcher: ${DEMO_SCRIPT}${NO_COLOR}"
echo -e "${CYAN}Dashboard:     http://${AP_IP}:4173${NO_COLOR}"
echo -e "${CYAN}Demo videos:   copy *.mp4 into ${DEMO_DIR}/videos${NO_COLOR}"
echo -e "${CYAN}Windows laptop: just run RunDemo.bat - it discovers this path automatically.${NO_COLOR}"
echo -e "${YELLOW}Run the demo once before the show: the first start pulls the container images.${NO_COLOR}"
echo -e "${YELLOW}Log out and back in (or reboot) so the new group memberships take effect.${NO_COLOR}"


