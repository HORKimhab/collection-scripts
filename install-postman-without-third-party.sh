#!/bin/bash

# Find debian architecture is amd64 or arm64
POSTMAN_URL_DOWNLOAD="https://dl.pstmn.io/download/latest"
ARCH=$(dpkg --print-architecture)

if [ "$ARCH" == "amd64" ]; then
  FILE="linux_64"
  echo "Architecture is amd64. You will be downloading Postman for x86_64..."
elif [ "$ARCH" == "arm64" ]; then
  FILE="linux_arm64"
  echo "Architecture is arm64. You will be Downloading Postman for ARM64..."
else
  echo "Unsupported architecture: $ARCH"
  exit 1
fi

# Prompt the user for an action
echo "Select an action:"
echo "1. Install or Upgrade Postman"
echo "2. Backup old Postman"
echo "1,2. Backup and Install/Upgrade Postman"
read -p "Enter your choice (1/2/1,2): " CHOICE

# Function to back up the old Postman
backup() {
  if [[ -d /opt/Postman ]]; then
    BACKUP_DIR_POSTMAN="/opt/Postman-backup-$(date +%Y%m%d%H%M%S)"
    echo "Backing up old Postman to $BACKUP_DIR_POSTMAN..."
    sudo mv /opt/Postman "$BACKUP_DIR_POSTMAN"
  else
    echo "No existing Postman installation found to back up."
  fi
}

# Function to install or upgrade Postman
install_or_upgrade() {
  # Delete old tarball if it exists
  sudo rm -rf "postman-${FILE}.tar.gz"

  # Download the appropriate file
  echo "Downloading Postman..."
  wget "${POSTMAN_URL_DOWNLOAD}/${FILE}" -O "postman-${FILE}.tar.gz"

  # Extract the downloaded Postman tarball to /opt
  echo "Extracting Postman to /opt..."
  sudo tar xvf "postman-${FILE}.tar.gz" -C /opt/

  # Delete old tarball if it exists
  sudo rm -rf "postman-${FILE}.tar.gz"

  # Create a symbolic link
  echo "Creating symbolic link..."
  sudo ln -sf /opt/Postman/app/Postman /usr/bin/postman

  # Create a desktop entry for Postman
  DESKTOP_ENTRY=~/.local/share/applications/postman.desktop
  echo "Creating desktop entry..."
  sudo truncate -s 0 "$DESKTOP_ENTRY"
  echo "[Desktop Entry]
Encoding=UTF-8
Name=Postman
X-GNOME-FullName=Postman API Client
Exec=/usr/bin/postman
Icon=/opt/Postman/app/resources/app/assets/icon.png
Terminal=false
Type=Application
Categories=Development;" | sudo tee "$DESKTOP_ENTRY" >/dev/null

  sudo chmod +x "$DESKTOP_ENTRY"

  echo "Postman installation or upgrade completed successfully."
}

# Process user choice
case "$CHOICE" in
1)
  install_or_upgrade
  ;;
2)
  backup
  ;;
1,2)
  backup
  install_or_upgrade
  ;;
*)
  print_with_dashes "Postman was not installed based on your selection."
  echo -e "Please verify your options to install or upgrade."
  exit 1
  ;;
esac
