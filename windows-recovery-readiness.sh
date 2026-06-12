#!/bin/bash

# Windows Password Reset Script using chntpw (Kali Linux)
# Based on: https://www.examcollection.com/blog/step-by-step-guide-to-reset-windows-passwords-via-kali-linux/
# Usage: sudo ./reset_windows_pass.sh
# Note: Not test yet

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}This script must be run as root (use sudo).${NC}" 
   exit 1
fi

# Check if chntpw is installed
if ! command -v chntpw &> /dev/null; then
    echo -e "${YELLOW}chntpw not found. Installing...${NC}"
    apt update && apt install -y chntpw
    if [ $? -ne 0 ]; then
        echo -e "${RED}Failed to install chntpw. Exiting.${NC}"
        exit 1
    fi
fi

echo -e "${GREEN}=== Windows Password Reset Tool (Kali Linux) ===${NC}"
echo ""

# Step 1: Detect Windows partitions
echo -e "${YELLOW}Detecting Windows NTFS partitions...${NC}"
WIN_PART=$(sudo fdisk -l | grep -i "NTFS" | awk '{print $1}' | head -n 1)

if [ -z "$WIN_PART" ]; then
    echo -e "${RED}No NTFS partition found. Is Windows installed on this disk?${NC}"
    exit 1
fi

echo -e "${GREEN}Found Windows partition: $WIN_PART${NC}"
echo ""

# Step 2: Create mount point and mount the partition
MOUNT_POINT="/mnt/windows"
mkdir -p $MOUNT_POINT

echo -e "${YELLOW}Mounting $WIN_PART to $MOUNT_POINT...${NC}"
mount -t ntfs-3g "$WIN_PART" "$MOUNT_POINT" 2>/dev/null

if [ $? -ne 0 ]; then
    echo -e "${RED}Mount failed. Possible reasons: Fast Startup/Hibernation enabled, or partition is damaged.${NC}"
    echo -e "${YELLOW}Try: boot into Windows and disable Fast Startup, then fully shut down.${NC}"
    exit 1
fi

# Step 3: Navigate to SAM file location
SAM_PATH="$MOUNT_POINT/Windows/System32/config/SAM"
SYSTEM_PATH="$MOUNT_POINT/Windows/System32/config/SYSTEM"

if [ ! -f "$SAM_PATH" ] || [ ! -f "$SYSTEM_PATH" ]; then
    echo -e "${RED}SAM or SYSTEM file not found. Is this the correct Windows partition?${NC}"
    umount "$MOUNT_POINT" 2>/dev/null
    exit 1
fi

echo -e "${GREEN}SAM and SYSTEM files located successfully.${NC}"
echo ""

# Step 4: List all Windows users
echo -e "${YELLOW}Listing Windows user accounts:${NC}"
chntpw -l "$SAM_PATH"
echo ""

# Step 5: Ask for username to reset
read -p "Enter the username to reset password for: " TARGET_USER
if [ -z "$TARGET_USER" ]; then
    echo -e "${RED}No username entered. Exiting.${NC}"
    umount "$MOUNT_POINT" 2>/dev/null
    exit 1
fi

# Step 6: Reset (clear) the password using chntpw interactive mode
echo -e "${YELLOW}Launching chntpw for user: $TARGET_USER${NC}"
echo -e "${GREEN}In the menu that appears:${NC}"
echo "  1. Press '1' to clear (blank) the user password"
echo "  2. Then press 'q' to quit, and 'y' to save changes"
echo ""
read -p "Press Enter to continue..."

chntpw -u "$TARGET_USER" "$SAM_PATH"

# Step 7: Ask for cleanup
echo ""
read -p "Password reset attempt completed. Unmount partition and reboot now? (y/n): " CLEANUP
if [[ "$CLEANUP" =~ ^[Yy]$ ]]; then
    echo -e "${YELLOW}Unmounting...${NC}"
    umount "$MOUNT_POINT" 2>/dev/null
    echo -e "${GREEN}Unmounted. Rebooting in 3 seconds...${NC}"
    sleep 3
    reboot
else
    echo -e "${YELLOW}Partition still mounted at $MOUNT_POINT. You can unmount manually: sudo umount $MOUNT_POINT${NC}"
fi

echo -e "${GREEN}Script finished.${NC}"