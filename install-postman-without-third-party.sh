#!/bin/bash

# Find debian architecture is amd64 or arm64
POSTMAN_URL_DOWNLOAD="https://dl.pstmn.io/download/latest"
ARCH=$(dpkg --print-architecture)

if [ "$ARCH" == "amd64" ]; then
  FILE="linux_64"
  echo "Architecture is amd64. Downloading Postman for x86_64..."
elif [ "$ARCH" == "arm64" ]; then
  FILE="linux_arm64"
  echo "Architecture is arm64. Downloading Postman for ARM64..."
else
  echo "Unsupported architecture: $ARCH"
  exit 1
fi

# Delete old file postman
sudo rm -rf "postman-${FILE}.tar.gz"

# Download the appropriate file
wget "${POSTMAN_URL_DOWNLOAD}/${FILE}" -O "postman-${FILE}.tar.gz"

# Delete old postman
sudo rm -rf /opt/Postman/

# Extract compress postman file to dir opt
sudo tar xvf "postman-${FILE}.tar.gz" -C /opt/

# Create link
sudo ln -sf /opt/Postman/app/Postman /usr/bin/postman

# Create postman as app in desktop app or can search it
sudo truncate -s 0 ~/.local/share/applications/postman.desktop

echo "[Desktop Entry]
Encoding=UTF-8
Name=Postman
X-GNOME-FullName=Postman API Client
Exec=/usr/bin/postman
Icon=/opt/Postman/app/resources/app/assets/icon.png
Terminal=false
Type=Application
Categories=Development;" | sudo tee ~/.local/share/applications/postman.desktop >/dev/null

sudo chmod +x ~/.local/share/applications/postman.desktop
