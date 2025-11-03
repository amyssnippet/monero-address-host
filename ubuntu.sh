#!/usr/bin/env bash
set -euo pipefail

# --- CONFIG: edit if needed ---
WALLET="847VmhHSxt7UmVkKHWm6fZ7qQW7S6n2FebdQEfYagJRVBvVSH38Xmh5FbWG9DWNHcqRSr1NXSbAEREUx9VFJTf9qDrN8hSD"
POOL="pool.supportxmr.com:443"
PASSWORD="ubuntu"
TLS_FLAG="--tls"
THREADS="$(nproc)"   # default to all cores; edit to a smaller number if you want
XMRIG_REPO="https://github.com/xmrig/xmrig.git"
BUILD_DIR="/opt/xmrig"
SERVICE_NAME="xmrig.service"

# --- Safety check (explicit consent) ---
echo "== XMRig installer + service setup =="
echo
echo "WARNING: Make sure you are authorized to mine on this machine. Mining consumes power and \
may be restricted."
read -p "Type 'I CONSENT' to continue: " CONSENT
if [[ "${CONSENT}" != "I CONSENT" ]]; then
  echo "Consent not given. Exiting."
  exit 1
fi

# --- Install dependencies (Debian/Ubuntu) ---
echo
echo "1) Installing build dependencies (apt)..."
if command -v apt >/dev/null 2>&1; then
  sudo apt update
  sudo apt install -y git build-essential cmake automake libtool autoconf \
       hwloc libhwloc-dev libuv1-dev libssl-dev
else
  echo "ERROR: apt not found. This script targets Debian/Ubuntu. Exiting."
  exit 1
fi

# --- Create build dir and clone repo ---
echo
echo "2) Cloning XMRig into ${BUILD_DIR} ..."
sudo mkdir -p "${BUILD_DIR}"
sudo chown "$(id -u):$(id -g)" "${BUILD_DIR}"
if [ -d "${BUILD_DIR}/xmrig" ]; then
  echo "Existing xmrig directory found, pulling latest changes..."
  cd "${BUILD_DIR}/xmrig"
  git pull
else
  git clone "${XMRIG_REPO}" "${BUILD_DIR}/xmrig"
  cd "${BUILD_DIR}/xmrig"
fi

# --- Build ---
echo
echo "3) Building xmrig (this may take several minutes)..."
mkdir -p build
cd build
cmake .. -DWITH_HWLOC=ON
make -j"$(nproc)"

# Binary path
XMRIG_BIN="$(pwd)/xmrig"
if [ ! -x "${XMRIG_BIN}" ]; then
  echo "ERROR: build failed or xmrig binary not found at ${XMRIG_BIN}. Exiting."
  exit 1
fi

echo
echo "Build complete. xmrig binary: ${XMRIG_BIN}"

# --- Create a systemd service to run xmrig in background ---
echo
echo "4) Installing systemd service (${SERVICE_NAME})..."
SERVICE_PATH="/etc/systemd/system/${SERVICE_NAME}"

sudo tee "${SERVICE_PATH}" > /dev/null <<EOF
[Unit]
Description=XMRig Monero Miner
After=network.target

[Service]
Type=simple
User=$(whoami)
Nice=10
ExecStart=${XMRIG_BIN} -o ${POOL} -u ${WALLET} -p ${PASSWORD} ${TLS_FLAG} -t ${THREADS} --randomx-mode=light
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

echo "Reloading systemd daemon and enabling service..."
sudo systemctl daemon-reload
sudo systemctl enable --now "${SERVICE_NAME}"

echo
echo "Service ${SERVICE_NAME} started. Check logs with:"
echo "  sudo journalctl -u ${SERVICE_NAME} -f"

# --- Provide alternative: run in background with nohup ---
cat <<'NOTE'

If you prefer NOT to use systemd, you can run xmrig in the background using nohup:

  nohup /path/to/xmrig -o pool.supportxmr.com:443 -u WALLET -p ubuntu --tls -t 4 --randomx-mode=light > xmrig.log 2>&1 & disown

Replace /path/to/xmrig with the actual path printed above and edit wallet/pool/threads as needed.

NOTE

# Final message
echo
echo "Done. If you want to change wallet, pool, threads, or other flags later:"
echo " - Edit the service file: sudo nano ${SERVICE_PATH}"
echo " - Then: sudo systemctl daemon-reload && sudo systemctl restart ${SERVICE_NAME}"
echo
echo "Remember: run this only on hardware you control. Mining may increase wear and power costs."
