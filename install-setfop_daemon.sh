#!/bin/bash

set -e

REPO_URL="https://github.com/SETFOP/setfop/raw/refs/heads/main/setfop-daemon-1.0.0.zip"

INSTALL_DIR="/opt/setfop-daemon"
SERVICE_FILE="setfop-daemon.service"

LOG_DIR="/var/log/setfop"
CONFIG_DIR="/etc/setfop"
LIB_DIR="/var/lib/setfop"

echo "[INFO] Installing setfop-daemon..."

if [[ $EUID -ne 0 ]]; then
echo "[ERROR] Run as root"
exit 1
fi

echo "[INFO] Ensuring dependency python3-inotify is installed"

if ! dpkg -s python3-inotify >/dev/null 2>&1; then
   apt update
   apt install -y python3-inotify
fi

echo "[INFO] Creating directories"

mkdir -p "$INSTALL_DIR"
mkdir -p "$LOG_DIR"
mkdir -p "$CONFIG_DIR"
mkdir -p "$LIB_DIR"

echo "[INFO] Downloading setfop-daemon package"

cd /tmp

ARCHIVE="/tmp/setfop-daemon.zip"

curl -fL "$REPO_URL" -o "$ARCHIVE"

if [ $? -ne 0 ]; then
   echo "[ERROR] Download failed"
   exit 1
fi

echo "[INFO] Verifying archive"

if ! file "$ARCHIVE" | grep -q "Zip archive"; then
   echo "[ERROR] Downloaded file is not a valid ZIP archive"
   exit 1
fi

echo "[INFO] Extracting archive"

apt install -y unzip >/dev/null

unzip -o "$ARCHIVE";echo "[INFO] Downloading setfop-daemon package"

cd /tmp

ARCHIVE="/tmp/setfop-daemon.zip"

curl -fL "$REPO_URL" -o "$ARCHIVE"

if [ $? -ne 0 ]; then
   echo "[ERROR] Download failed"
   exit 1
fi

echo "[INFO] Verifying archive"

if ! file "$ARCHIVE" | grep -q "Zip archive"; then
   echo "[ERROR] Downloaded file is not a valid ZIP archive"
   exit 1
fi

echo "[INFO] Extracting archive"

apt install -y unzip >/dev/null

unzip -o "$ARCHIVE"

echo "[INFO] Copying files"

cp -r setfop-daemon-main/* "$INSTALL_DIR"

chmod +x "$INSTALL_DIR/bin/setfop-daemon.py"
chmod +x "$INSTALL_DIR/scripts/"*.sh

echo "[INFO] Creating drift log"

touch "$LOG_DIR/drift.log"
chmod 644 "$LOG_DIR/drift.log"

echo "[INFO] Installing systemd service"

cp "$INSTALL_DIR/setfop-daemon.service" /etc/systemd/system/

systemctl daemon-reload
systemctl enable setfop-daemon

echo "[INFO] Installing logrotate"

cp "$INSTALL_DIR/setfop-daemon.logrotate" /etc/logrotate.d/setfop-daemon

echo "[INFO] Starting daemon"

systemctl start setfop-daemon

echo "[SUCCESS] setfop-daemon installed"
